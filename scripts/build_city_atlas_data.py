#!/usr/bin/env python3
"""Build the offline City Chain atlas bundle from Census 2024 source files.

Requires pyshp 2.3.1 and Shapely 2.1.1 (see scripts/requirements-city-atlas.txt).
The catalog is read from Sources/CityChainGame/USCity.swift so this script
cannot silently drift from the app's curated 150-city reply catalog.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import re
import sys
import urllib.request
import zipfile
from pathlib import Path

import shapefile
from shapely import coverage_is_valid, coverage_simplify, orient_polygons
from shapely.geometry import mapping, shape


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "CityChainApp/Resources/Atlas"
CATALOG_SOURCE = ROOT / "Sources/CityChainGame/USCity.swift"
SOURCES = {
    "states": {
        "url": "https://www2.census.gov/geo/tiger/TIGER2024/STATE/tl_2024_us_state.zip",
        "sha256": "ad00cbe66c7177091b668cee202e93d4a1ddcee271c28d1c9f9874af59c04b92",
        "archive_member": "tl_2024_us_state.shp",
    },
    "places": {
        "url": "https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2024_Gazetteer/2024_Gaz_place_national.zip",
        "sha256": "cf262fc92b2326f7a8c62a89d156a60eb17d64d6d35f7a62310c43bb08972c06",
        "archive_member": "2024_Gaz_place_national.txt",
    },
}
STATE_CODES = {
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
    "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
    "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
    "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
    "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY",
}

# Only names that cannot be resolved to one Gazetteer place by normalized
# city + state matching belong here. Values are Census place GEOIDs.
GEOID_OVERRIDES: dict[tuple[str, str], str] = {
    # Honolulu is a consolidated city-county without a matching Census place
    # named "Honolulu" in this file. Urban Honolulu CDP is the documented
    # Census representative point used for the catalog's Honolulu entry.
    ("Honolulu", "HI"): "1571550",
    # The game catalog spells this municipality's formal place name out.
    ("Saint Paul", "MN"): "2758000",
    # Nashville's Census place is the consolidated metro-government balance.
    ("Nashville", "TN"): "4752006",
    # Census retains "City" in the proper place name "Boise City".
    ("Boise", "ID"): "1608830",
}

STATE_ABBREVIATIONS: dict[str, str] = {
    "alabama": "AL", "alaska": "AK", "arizona": "AZ", "arkansas": "AR",
    "california": "CA", "colorado": "CO", "connecticut": "CT", "delaware": "DE",
    "florida": "FL", "georgia": "GA", "hawaii": "HI", "idaho": "ID",
    "illinois": "IL", "indiana": "IN", "iowa": "IA", "kansas": "KS",
    "kentucky": "KY", "louisiana": "LA", "maine": "ME", "maryland": "MD",
    "massachusetts": "MA", "michigan": "MI", "minnesota": "MN", "mississippi": "MS",
    "missouri": "MO", "montana": "MT", "nebraska": "NE", "nevada": "NV",
    "newHampshire": "NH", "newJersey": "NJ", "newMexico": "NM", "newYork": "NY",
    "northCarolina": "NC", "northDakota": "ND", "ohio": "OH", "oklahoma": "OK",
    "oregon": "OR", "pennsylvania": "PA", "rhodeIsland": "RI", "southCarolina": "SC",
    "southDakota": "SD", "tennessee": "TN", "texas": "TX", "utah": "UT",
    "vermont": "VT", "virginia": "VA", "washington": "WA", "westVirginia": "WV",
    "wisconsin": "WI", "wyoming": "WY",
}
PLACE_SUFFIXES = (
    " city and borough", " metropolitan government (balance)", " city (balance)",
    " metropolitan government", " urban county", " municipality", " plantation",
    " township", " borough", " village", " town", " city", " cdp", " (balance)",
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fetch(name: str, cache: Path) -> bytes:
    source = SOURCES[name]
    cache.mkdir(parents=True, exist_ok=True)
    path = cache / Path(source["url"]).name
    if not path.exists():
        print(f"Downloading {source['url']}", file=sys.stderr)
        urllib.request.urlretrieve(source["url"], path)
    data = path.read_bytes()
    actual = sha256(data)
    if actual != source["sha256"]:
        raise ValueError(f"{path}: SHA-256 {actual} does not match pinned {source['sha256']}")
    return data


def normalized(value: str) -> str:
    return "".join(ch.lower() for ch in value if ch.isalnum())


def base_place_name(value: str) -> str:
    value = value.strip()
    for suffix in PLACE_SUFFIXES:
        if value.lower().endswith(suffix):
            return value[:-len(suffix)].strip()
    return value


def place_name_matches(place_name: str, city_name: str) -> bool:
    target = normalized(city_name)
    # Preserve exact full-name matches first (e.g. Carson City, where "City"
    # is part of the name and not a Census place-type suffix).
    return normalized(place_name) == target or normalized(base_place_name(place_name)) == target


def catalog_rows() -> list[dict[str, object]]:
    source = CATALOG_SOURCE.read_text()
    pattern = re.compile(
        r'USCity\("(?P<name>(?:[^"\\]|\\.)*)",\s*state:\s*\.(?P<state>\w+)'
        r'(?P<capital>,\s*isStateCapital:\s*true)?\)'
    )
    rows = []
    for match in pattern.finditer(source):
        state_key = match.group("state")
        abbreviation = STATE_ABBREVIATIONS.get(state_key)
        if abbreviation is None:
            continue
        rows.append({
            "name": match.group("name"),
            "state": state_key,
            "stateAbbreviation": abbreviation,
            "isStateCapital": bool(match.group("capital")),
        })
    if len(rows) != 150:
        raise ValueError(f"Expected the curated 150-city catalog, found {len(rows)} entries")
    if len({(normalized(str(row["name"])), row["stateAbbreviation"]) for row in rows}) != len(rows):
        raise ValueError("Catalog contains duplicate city/state pairs")
    return rows


def gazetteer_rows(data: bytes) -> list[dict[str, str]]:
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        raw = archive.read(SOURCES["places"]["archive_member"]).decode("utf-8-sig")
    rows = []
    for row in csv.DictReader(io.StringIO(raw), delimiter="\t"):
        row = {key.strip(): value.strip() for key, value in row.items() if key is not None and value is not None}
        if row["USPS"] in STATE_CODES:
            rows.append({
                "state": row["USPS"], "geoid": row["GEOID"], "name": row["NAME"],
                "latitude": row["INTPTLAT"], "longitude": row["INTPTLONG"],
            })
    return rows


def resolve_catalog(catalog: list[dict[str, object]], places: list[dict[str, str]]) -> list[dict[str, object]]:
    result = []
    for city in catalog:
        key = (str(city["name"]), str(city["stateAbbreviation"]))
        override = GEOID_OVERRIDES.get(key)
        candidates = [
            place for place in places
            if place["state"] == key[1]
            and place_name_matches(place["name"], key[0])
        ]
        if override:
            candidates = [place for place in places if place["geoid"] == override and place["state"] == key[1]]
            if len(candidates) != 1:
                raise ValueError(f"Invalid GEOID override for {key}: {override}")
        elif len(candidates) != 1:
            options = ", ".join(f"{p['geoid']} {p['name']}" for p in candidates) or "no match"
            raise ValueError(f"Expected one Census match for {key}, found {options}; curate its GEOID")
        place = candidates[0]
        result.append({
            "name": city["name"], "state": city["stateAbbreviation"],
            "isStateCapital": city["isStateCapital"], "geoid": place["geoid"],
            "censusPlaceName": place["name"],
            "latitude": float(place["latitude"]), "longitude": float(place["longitude"]),
            "source": "2024 Census Gazetteer Places representative point",
        })
    return result


def state_features(data: bytes) -> tuple[list[dict[str, object]], list[dict[str, object]], int, int, int, int]:
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        prefix = "tl_2024_us_state"
        reader = shapefile.Reader(
            shp=io.BytesIO(archive.read(prefix + ".shp")),
            shx=io.BytesIO(archive.read(prefix + ".shx")),
            dbf=io.BytesIO(archive.read(prefix + ".dbf")),
        )
        fields = [field[0] for field in reader.fields[1:]]
        index = {name: fields.index(name) for name in ("NAME", "STUSPS", "STATEFP", "GEOID")}
        source_features = []
        for item in reader.iterShapeRecords():
            properties = item.record
            abbreviation = properties[index["STUSPS"]]
            if abbreviation not in STATE_CODES:
                continue
            source_features.append({
                "type": "Feature",
                "id": abbreviation,
                "properties": {
                    "name": properties[index["NAME"]],
                    "abbreviation": abbreviation,
                    "stateFips": properties[index["STATEFP"]],
                    "geoid": properties[index["GEOID"]],
                },
                "geometry": shape(item.shape.__geo_interface__),
            })
        geometries = [feature["geometry"] for feature in source_features]
        if not coverage_is_valid(geometries):
            raise ValueError("TIGER state boundaries do not form a valid shared-edge coverage")
        detailed = coverage_simplify(geometries, tolerance=0.02, simplify_boundary=True)
        illustrative = coverage_simplify(geometries, tolerance=0.15, simplify_boundary=True)
        for label, simplified in (("detailed", detailed), ("illustrative", illustrative)):
            if not coverage_is_valid(simplified):
                raise ValueError(f"{label} TIGER boundaries failed shared-edge coverage validation")
            simplified = orient_polygons(simplified, exterior_cw=False)
            if not coverage_is_valid(simplified):
                raise ValueError(f"RFC 7946 ring orientation changed {label} coverage validity")
            if len(simplified) != 50 or any(geometry.is_empty or not geometry.is_valid for geometry in simplified):
                raise ValueError(f"{label} simplification removed or invalidated a state geometry")
            for feature, source_geometry, simplified_geometry in zip(
                source_features, geometries, simplified, strict=True
            ):
                source_parts = len(source_geometry.geoms) if source_geometry.geom_type == "MultiPolygon" else 1
                simplified_parts = len(simplified_geometry.geoms) if simplified_geometry.geom_type == "MultiPolygon" else 1
                if source_parts != simplified_parts:
                    raise ValueError(
                        f"{label} simplification changed the island/component count for "
                        f"{feature['properties']['abbreviation']}: {source_parts} to {simplified_parts}"
                    )
            if label == "detailed":
                detailed = simplified
            else:
                illustrative = simplified
        features = [
            {**feature, "geometry": mapping(geometry)}
            for feature, geometry in zip(source_features, detailed, strict=True)
        ]
        simplified_features = [
            {**feature, "geometry": mapping(geometry)}
            for feature, geometry in zip(source_features, illustrative, strict=True)
        ]
        def vertex_count(geometries: list[object]) -> int:
            return sum(
                len(ring.coords)
                for geometry in geometries
                for polygon in (list(geometry.geoms) if geometry.geom_type == "MultiPolygon" else [geometry])
                for ring in [*polygon.interiors, polygon.exterior]
            )

        detailed_vertices = vertex_count(detailed)
        illustrative_vertices = vertex_count(illustrative)
        texas_index = next(i for i, feature in enumerate(source_features) if feature["properties"]["abbreviation"] == "TX")
        texas_detailed_vertices = vertex_count([detailed[texas_index]])
        texas_illustrative_vertices = vertex_count([illustrative[texas_index]])
    if len(features) != 50:
        raise ValueError(f"Expected 50 state boundaries; found {len(features)}")
    return features, simplified_features, detailed_vertices, illustrative_vertices, texas_detailed_vertices, texas_illustrative_vertices


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=ROOT / ".build/city-atlas-source-cache")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    state_zip = fetch("states", args.cache)
    place_zip = fetch("places", args.cache)
    catalog = catalog_rows()
    places = gazetteer_rows(place_zip)
    points = resolve_catalog(catalog, places)
    features, simplified_features, detailed_vertices, illustrative_vertices, texas_detailed_vertices, texas_illustrative_vertices = state_features(state_zip)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "us-states-2024.geojson").write_text(json.dumps({
        "type": "FeatureCollection",
        "atlasMetadata": {
            "source": SOURCES["states"]["url"],
            "sourceSHA256": SOURCES["states"]["sha256"],
            "vintage": 2024,
            "simplification": "Shapely coverage_simplify on the source shared-edge coverage",
            "detailedToleranceDegrees": 0.02,
            "simpleToleranceDegrees": 0.15,
            "coordinateOrder": "longitude, latitude; NAD83 geographic degrees as published in TIGER .prj",
            "ringOrientation": "RFC 7946 right-hand rule",
        },
        "features": features,
        "atlasSimplifiedFeatures": simplified_features,
    }, separators=(",", ":")) + "\n")
    (args.output / "catalog-city-points-2024.json").write_text(json.dumps({
        "source": "2024 Census Gazetteer Places representative points",
        "coordinateReference": "NAD83 geographic degrees as published",
        "cities": points,
    }, separators=(",", ":")) + "\n")
    print(
        f"Wrote detailed boundaries ({detailed_vertices} vertices; TX {texas_detailed_vertices}) and "
        f"simple boundaries ({illustrative_vertices} vertices; TX {texas_illustrative_vertices}, "
        f"tolerance 0.15 degrees) "
        f"and {len(points)} catalog points to {args.output}"
    )


if __name__ == "__main__":
    main()
