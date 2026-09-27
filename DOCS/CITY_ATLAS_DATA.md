# Pocket Atlas data

The app bundles its atlas and works offline. The state layer contains 50 TIGER/Line 2024 state and equivalent entity boundaries. The city layer contains representative points for the app's curated 150-city catalog, matched by city and state to the 2024 Census Gazetteer Places file. A point is a Census representative point, not a city center or a driving destination.

## Sources and attribution

- [TIGER/Line Shapefile 2024: nation U.S. state and equivalent entities](https://catalog.data.gov/dataset/tiger-line-shapefile-2024-nation-u-s-state-and-equivalent-entities), source archive: [`tl_2024_us_state.zip`](https://www2.census.gov/geo/tiger/TIGER2024/STATE/tl_2024_us_state.zip).
- [2024 Census Gazetteer Files](https://www.census.gov/geographies/reference-files/time-series/geo/gazetteer-files.2024.html), Places archive: [`2024_Gaz_place_national.zip`](https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2024_Gazetteer/2024_Gaz_place_national.zip).
- U.S. Census Bureau government works are generally public domain under 17 U.S.C. § 105. The Census Bureau's TIGER/Line product carries its own disclaimer; this attribution does not claim every third-party repackaging or derived product is CC0.

The source ZIPs are pinned by SHA-256 in `scripts/build_city_atlas_data.py`. The script downloads them into the ignored local `.build/city-atlas-source-cache` directory. They are not included in the app bundle.

## Rebuild

Use Python 3.10 or newer. Shapely's shared-coverage simplifier needs GEOS 3.12 or newer; the pinned Shapely wheel supplies a compatible GEOS build.

```sh
python3 -m venv /tmp/city-atlas-venv
/tmp/city-atlas-venv/bin/python -m pip install -r scripts/requirements-city-atlas.txt
/tmp/city-atlas-venv/bin/python scripts/build_city_atlas_data.py
```

Generated resources are:

- `CityChainApp/Resources/Atlas/us-states-2024.geojson`
- `CityChainApp/Resources/Atlas/catalog-city-points-2024.json`

The GeoJSON uses NAD83 longitude/latitude coordinates as published in the TIGER projection file. The preprocessing script verifies the original state geometries form a valid shared-edge coverage, then derives two levels directly from that coverage with Shapely's topology-preserving `coverage_simplify`. Detailed uses 0.02 degrees and Simple uses 0.15 degrees. Both outputs are checked for valid coverage, valid state geometry, unchanged 50-state identity, and retained polygon component counts; both use RFC 7946 exterior/interior ring winding. Detailed has 10,532 vertices; Simple has 1,779. Texas has 533 detailed vertices and 65 Simple vertices, including ring closure. The complete GeoJSON is about 295 KB. Simple retains every state boundary while smoothing small boundary wiggles; it is illustrative and its borders are not intended for precise geographic measurement. State boundaries and city points use the same local equirectangular display projection. Alaska longitudes east of 0° are unwrapped across the antimeridian only inside the Alaska inset; Hawaii uses a separate inset. Both insets are labeled.

The atlas defaults to Simple, which shows all state boundaries with reduced geometric detail. Detailed uses the 0.02-degree state boundaries. Both modes retain identical state colors, visited-city markers, and same-region route segments. Map markers are shown only for visited cities with an exact catalog city/state point. A valid game city outside the catalog or without a verified match has no marker; the atlas says its position is unavailable instead of placing it at a default coordinate.

The catalog includes four explicit Gazetteer GEOID overrides: Boise maps to the source place name “Boise City”; Honolulu maps to “Urban Honolulu CDP” because no Gazetteer place named Honolulu exists; Saint Paul maps to “St. Paul city”; and Nashville maps to “Nashville-Davidson metropolitan government (balance)”. The generated point JSON keeps both app and source names plus GEOID so these decisions can be audited.
