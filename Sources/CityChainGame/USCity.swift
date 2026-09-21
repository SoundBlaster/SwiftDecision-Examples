import Foundation
import SpecificationCore

/// A US city name used by the game. User-entered cities do not need to be in the reply catalog.
public struct USCity: Hashable, Identifiable, Sendable, CustomStringConvertible {
  public let name: String

  /// A case- and punctuation-insensitive key used to prevent reusing a city.
  public var id: String {
    let folded = name.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
    return String(folded.filter { $0.isLetter || $0.isNumber }.map { Character($0.lowercased()) })
  }

  public var description: String { name }

  public var firstLetter: Character? { latinLetters.first }

  public var lastLetter: Character? { latinLetters.last }

  public init(_ name: String) {
    self.name = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  private var latinLetters: [Character] {
    let folded = name.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    ).uppercased()
    return folded.filter { $0 >= "A" && $0 <= "Z" }
  }
}

/// Ordered candidates the computer may use. Player input is validated independently by Noul.
public struct USCityCatalog: Sendable {
  public let cities: [USCity]

  public init(cities: [USCity]) {
    let isNotAlreadyIncluded = AnySpecification<CatalogDeduplicationContext> { context in
      !context.seenCityIDs.contains(context.city.id)
    }
    var seen = Set<String>()
    var uniqueCities: [USCity] = []
    for city in cities {
      if isNotAlreadyIncluded.isSatisfiedBy(
        CatalogDeduplicationContext(city: city, seenCityIDs: seen))
      {
        uniqueCities.append(city)
        seen.insert(city.id)
      }
    }
    self.cities = uniqueCities
  }

  public static let standard = USCityCatalog(cities: stateCapitals + majorCities)

  /// The 50 state capitals, in state-name order.
  public static let stateCapitals: [USCity] = [
    "Montgomery", "Juneau", "Phoenix", "Little Rock", "Sacramento", "Denver", "Hartford", "Dover",
    "Tallahassee", "Atlanta", "Honolulu", "Boise", "Springfield", "Indianapolis", "Des Moines",
    "Topeka",
    "Frankfort", "Baton Rouge", "Augusta", "Annapolis", "Boston", "Lansing", "Saint Paul",
    "Jackson",
    "Jefferson City", "Helena", "Lincoln", "Carson City", "Concord", "Trenton", "Santa Fe",
    "Albany",
    "Raleigh", "Bismarck", "Columbus", "Oklahoma City", "Salem", "Harrisburg", "Providence",
    "Columbia",
    "Pierre", "Nashville", "Austin", "Salt Lake City", "Montpelier", "Richmond", "Olympia",
    "Charleston",
    "Madison", "Cheyenne",
  ].map(USCity.init)

  /// Fifty additional large US cities, selected to avoid duplicating the state-capital list.
  public static let majorCities: [USCity] = [
    "New York", "Los Angeles", "Chicago", "Houston", "San Antonio", "San Diego", "Dallas",
    "San Jose",
    "Jacksonville", "Fort Worth", "El Paso", "Detroit", "Memphis", "Portland", "Louisville",
    "Baltimore",
    "Milwaukee", "Albuquerque", "Tucson", "Fresno", "Mesa", "Kansas City", "Miami", "Long Beach",
    "Virginia Beach", "Oakland", "Minneapolis", "Tampa", "Tulsa", "Arlington", "New Orleans",
    "Wichita",
    "Cleveland", "Bakersfield", "Aurora", "Anaheim", "Santa Ana", "Riverside", "Corpus Christi",
    "Stockton",
    "Pittsburgh", "Cincinnati", "St. Louis", "Orlando", "Newark", "Greensboro", "Jersey City",
    "Laredo",
    "Scottsdale", "Seattle",
  ].map(USCity.init)
}

private struct CatalogDeduplicationContext {
  let city: USCity
  let seenCityIDs: Set<String>
}
