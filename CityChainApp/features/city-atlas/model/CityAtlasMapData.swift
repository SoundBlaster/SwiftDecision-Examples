import CityChainGame
import Foundation
import SwiftUI

struct CityAtlasPoint: Decodable, Identifiable, Hashable {
  let name: String
  let state: String
  let isStateCapital: Bool
  let geoid: String
  let censusPlaceName: String
  let latitude: Double
  let longitude: Double

  var id: String { "\(state):\(geoid)" }
}

struct CityAtlasMapData {
  enum Region: String, Hashable {
    case mainland
    case alaska
    case hawaii
  }

  struct StateShape: Identifiable {
    let id: String
    let name: String
    let abbreviation: String
    let region: Region
    let path: Path
    let simplePath: Path
  }

  let states: [StateShape]
  let points: [String: CityAtlasPoint]

  static func load(bundle: Bundle = .main) -> CityAtlasMapData? {
    guard
      let boundaryURL = bundle.url(forResource: "us-states-2024", withExtension: "geojson"),
      let pointsURL = bundle.url(forResource: "catalog-city-points-2024", withExtension: "json"),
      let boundaryData = try? Data(contentsOf: boundaryURL),
      let pointData = try? Data(contentsOf: pointsURL),
      let collection = try? JSONSerialization.jsonObject(with: boundaryData) as? [String: Any],
      let features = collection["features"] as? [[String: Any]],
      let simplifiedFeatures = collection["atlasSimplifiedFeatures"] as? [[String: Any]],
      let pointJSON = try? JSONDecoder().decode(CityAtlasPointCollection.self, from: pointData)
    else { return nil }

    let simplifiedByState = Dictionary(
      uniqueKeysWithValues: simplifiedFeatures.compactMap { feature -> (String, [String: Any])? in
        guard
          let properties = feature["properties"] as? [String: String],
          let abbreviation = properties["abbreviation"],
          let geometry = feature["geometry"] as? [String: Any]
        else { return nil }
        return (abbreviation, geometry)
      })

    let stateShapes = features.compactMap { feature -> StateShape? in
      guard
        let properties = feature["properties"] as? [String: String],
        let abbreviation = properties["abbreviation"],
        let stateName = properties["name"],
        let geometry = feature["geometry"] as? [String: Any],
        let simpleGeometry = simplifiedByState[abbreviation]
      else { return nil }

      let region: Region = switch abbreviation {
      case "AK": .alaska
      case "HI": .hawaii
      default: .mainland
      }
      guard
        let path = Self.path(geometry: geometry, region: region),
        let simplePath = Self.path(geometry: simpleGeometry, region: region)
      else { return nil }

      return StateShape(
        id: abbreviation, name: stateName, abbreviation: abbreviation,
        region: region, path: path, simplePath: simplePath)
    }

    guard stateShapes.count == 50 else { return nil }
    return CityAtlasMapData(
      states: stateShapes,
      points: Dictionary(uniqueKeysWithValues: pointJSON.cities.map { ($0.id, $0) }))
  }

  private static func path(geometry: [String: Any], region: Region) -> Path? {
    guard let type = geometry["type"] as? String, let coordinates = geometry["coordinates"] else { return nil }
    let polygons: [[[[NSNumber]]]]
    if type == "Polygon", let polygon = coordinates as? [[[NSNumber]]] {
      polygons = [polygon]
    } else if type == "MultiPolygon", let multipolygon = coordinates as? [[[[NSNumber]]]] {
      polygons = multipolygon
    } else {
      return nil
    }

    var path = Path()
    for polygon in polygons {
      for ring in polygon {
        let points = ring.compactMap { coordinate -> CGPoint? in
          guard coordinate.count >= 2 else { return nil }
          return normalizedPoint(
            longitude: coordinate[0].doubleValue,
            latitude: coordinate[1].doubleValue,
            region: region)
        }
        guard let first = points.first, points.count >= 4 else { continue }
        path.move(to: CGPoint(x: first.x * 1000, y: first.y * 1000))
        for point in points.dropFirst() {
          path.addLine(to: CGPoint(x: point.x * 1000, y: point.y * 1000))
        }
        path.closeSubpath()
      }
    }
    return path.isEmpty ? nil : path
  }

  func point(for city: USCity) -> CityAtlasPoint? {
    guard let state = city.stateAbbreviation else { return nil }
    let candidates = points.values.filter { $0.state == state && normalizedName($0.name) == normalizedName(city.name) }
    return candidates.first
  }

  func projectedPoint(for point: CityAtlasPoint) -> (region: Region, point: CGPoint) {
    let region: Region = switch point.state {
    case "AK": .alaska
    case "HI": .hawaii
    default: .mainland
    }
    return (region, Self.normalizedPoint(longitude: point.longitude, latitude: point.latitude, region: region))
  }

  static func bounds(for region: Region) -> (west: Double, east: Double, south: Double, north: Double) {
    switch region {
    case .mainland: (-125, -66, 24, 50)
    case .alaska: (-190, -129, 51, 72)
    case .hawaii: (-179, -154, 18, 29)
    }
  }

  private static func normalizedPoint(longitude: Double, latitude: Double, region: Region) -> CGPoint {
    let bounds = bounds(for: region)
    let unwrappedLongitude = region == .alaska && longitude > 0 ? longitude - 360 : longitude
    // Map locally into the same unit projection for both source polygons and
    // Gazetteer representative points. Alaska and Hawaii get labeled insets.
    return CGPoint(
      x: (unwrappedLongitude - bounds.west) / (bounds.east - bounds.west),
      y: (bounds.north - latitude) / (bounds.north - bounds.south))
  }

  private func normalizedName(_ name: String) -> String {
    String(name.lowercased().filter(\.isLetter))
  }
}

private struct CityAtlasPointCollection: Decodable {
  let cities: [CityAtlasPoint]
}

@MainActor
enum CityAtlasMapRepository {
  static let data = CityAtlasMapData.load()
}
