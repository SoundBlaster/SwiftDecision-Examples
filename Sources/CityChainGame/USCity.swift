import Foundation
import SpecificationCore

/// A US state used to identify a city in the game's atlas.
public enum USState: String, CaseIterable, Identifiable, Sendable {
  case alabama = "Alabama"
  case alaska = "Alaska"
  case arizona = "Arizona"
  case arkansas = "Arkansas"
  case california = "California"
  case colorado = "Colorado"
  case connecticut = "Connecticut"
  case delaware = "Delaware"
  case florida = "Florida"
  case georgia = "Georgia"
  case hawaii = "Hawaii"
  case idaho = "Idaho"
  case illinois = "Illinois"
  case indiana = "Indiana"
  case iowa = "Iowa"
  case kansas = "Kansas"
  case kentucky = "Kentucky"
  case louisiana = "Louisiana"
  case maine = "Maine"
  case maryland = "Maryland"
  case massachusetts = "Massachusetts"
  case michigan = "Michigan"
  case minnesota = "Minnesota"
  case mississippi = "Mississippi"
  case missouri = "Missouri"
  case montana = "Montana"
  case nebraska = "Nebraska"
  case nevada = "Nevada"
  case newHampshire = "New Hampshire"
  case newJersey = "New Jersey"
  case newMexico = "New Mexico"
  case newYork = "New York"
  case northCarolina = "North Carolina"
  case northDakota = "North Dakota"
  case ohio = "Ohio"
  case oklahoma = "Oklahoma"
  case oregon = "Oregon"
  case pennsylvania = "Pennsylvania"
  case rhodeIsland = "Rhode Island"
  case southCarolina = "South Carolina"
  case southDakota = "South Dakota"
  case tennessee = "Tennessee"
  case texas = "Texas"
  case utah = "Utah"
  case vermont = "Vermont"
  case virginia = "Virginia"
  case washington = "Washington"
  case westVirginia = "West Virginia"
  case wisconsin = "Wisconsin"
  case wyoming = "Wyoming"

  public var name: String { rawValue }

  public var id: String { abbreviation }

  public var abbreviation: String {
    switch self {
    case .alabama: "AL"
    case .alaska: "AK"
    case .arizona: "AZ"
    case .arkansas: "AR"
    case .california: "CA"
    case .colorado: "CO"
    case .connecticut: "CT"
    case .delaware: "DE"
    case .florida: "FL"
    case .georgia: "GA"
    case .hawaii: "HI"
    case .idaho: "ID"
    case .illinois: "IL"
    case .indiana: "IN"
    case .iowa: "IA"
    case .kansas: "KS"
    case .kentucky: "KY"
    case .louisiana: "LA"
    case .maine: "ME"
    case .maryland: "MD"
    case .massachusetts: "MA"
    case .michigan: "MI"
    case .minnesota: "MN"
    case .mississippi: "MS"
    case .missouri: "MO"
    case .montana: "MT"
    case .nebraska: "NE"
    case .nevada: "NV"
    case .newHampshire: "NH"
    case .newJersey: "NJ"
    case .newMexico: "NM"
    case .newYork: "NY"
    case .northCarolina: "NC"
    case .northDakota: "ND"
    case .ohio: "OH"
    case .oklahoma: "OK"
    case .oregon: "OR"
    case .pennsylvania: "PA"
    case .rhodeIsland: "RI"
    case .southCarolina: "SC"
    case .southDakota: "SD"
    case .tennessee: "TN"
    case .texas: "TX"
    case .utah: "UT"
    case .vermont: "VT"
    case .virginia: "VA"
    case .washington: "WA"
    case .westVirginia: "WV"
    case .wisconsin: "WI"
    case .wyoming: "WY"
    }
  }
}

/// A US city name used by the game. User-entered cities do not need to be in the reply catalog.
public struct USCity: Hashable, Identifiable, Sendable, CustomStringConvertible {
  public let name: String
  public let state: USState?
  public let isStateCapital: Bool

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

  var continuationLetters: [Character] { Array(latinLetters.reversed()) }

  public var stateName: String? { state?.name }

  public var stateAbbreviation: String? { state?.abbreviation }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.id == rhs.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  public init(_ name: String, state: USState? = nil, isStateCapital: Bool = false) {
    self.name = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    self.state = state
    self.isStateCapital = isStateCapital
  }

  private var latinLetters: [Character] {
    let folded = name.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    ).uppercased()
    return folded.filter { $0 >= "A" && $0 <= "Z" }
  }
}

/// Ordered candidates the computer may use. Player-entered cities are validated independently.
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

  public static let standard = USCityCatalog(cities: stateCapitals + majorCities + explorationCities)

  /// The 50 state capitals, in state-name order.
  public static let stateCapitals: [USCity] = [
    USCity("Montgomery", state: .alabama, isStateCapital: true),
    USCity("Juneau", state: .alaska, isStateCapital: true),
    USCity("Phoenix", state: .arizona, isStateCapital: true),
    USCity("Little Rock", state: .arkansas, isStateCapital: true),
    USCity("Sacramento", state: .california, isStateCapital: true),
    USCity("Denver", state: .colorado, isStateCapital: true),
    USCity("Hartford", state: .connecticut, isStateCapital: true),
    USCity("Dover", state: .delaware, isStateCapital: true),
    USCity("Tallahassee", state: .florida, isStateCapital: true),
    USCity("Atlanta", state: .georgia, isStateCapital: true),
    USCity("Honolulu", state: .hawaii, isStateCapital: true),
    USCity("Boise", state: .idaho, isStateCapital: true),
    USCity("Springfield", state: .illinois, isStateCapital: true),
    USCity("Indianapolis", state: .indiana, isStateCapital: true),
    USCity("Des Moines", state: .iowa, isStateCapital: true),
    USCity("Topeka", state: .kansas, isStateCapital: true),
    USCity("Frankfort", state: .kentucky, isStateCapital: true),
    USCity("Baton Rouge", state: .louisiana, isStateCapital: true),
    USCity("Augusta", state: .maine, isStateCapital: true),
    USCity("Annapolis", state: .maryland, isStateCapital: true),
    USCity("Boston", state: .massachusetts, isStateCapital: true),
    USCity("Lansing", state: .michigan, isStateCapital: true),
    USCity("Saint Paul", state: .minnesota, isStateCapital: true),
    USCity("Jackson", state: .mississippi, isStateCapital: true),
    USCity("Jefferson City", state: .missouri, isStateCapital: true),
    USCity("Helena", state: .montana, isStateCapital: true),
    USCity("Lincoln", state: .nebraska, isStateCapital: true),
    USCity("Carson City", state: .nevada, isStateCapital: true),
    USCity("Concord", state: .newHampshire, isStateCapital: true),
    USCity("Trenton", state: .newJersey, isStateCapital: true),
    USCity("Santa Fe", state: .newMexico, isStateCapital: true),
    USCity("Albany", state: .newYork, isStateCapital: true),
    USCity("Raleigh", state: .northCarolina, isStateCapital: true),
    USCity("Bismarck", state: .northDakota, isStateCapital: true),
    USCity("Columbus", state: .ohio, isStateCapital: true),
    USCity("Oklahoma City", state: .oklahoma, isStateCapital: true),
    USCity("Salem", state: .oregon, isStateCapital: true),
    USCity("Harrisburg", state: .pennsylvania, isStateCapital: true),
    USCity("Providence", state: .rhodeIsland, isStateCapital: true),
    USCity("Columbia", state: .southCarolina, isStateCapital: true),
    USCity("Pierre", state: .southDakota, isStateCapital: true),
    USCity("Nashville", state: .tennessee, isStateCapital: true),
    USCity("Austin", state: .texas, isStateCapital: true),
    USCity("Salt Lake City", state: .utah, isStateCapital: true),
    USCity("Montpelier", state: .vermont, isStateCapital: true),
    USCity("Richmond", state: .virginia, isStateCapital: true),
    USCity("Olympia", state: .washington, isStateCapital: true),
    USCity("Charleston", state: .westVirginia, isStateCapital: true),
    USCity("Madison", state: .wisconsin, isStateCapital: true),
    USCity("Cheyenne", state: .wyoming, isStateCapital: true),
  ]

  /// Fifty additional large US cities, selected to avoid duplicating the state-capital list.
  public static let majorCities: [USCity] = [
    USCity("New York", state: .newYork),
    USCity("Los Angeles", state: .california),
    USCity("Chicago", state: .illinois),
    USCity("Houston", state: .texas),
    USCity("San Antonio", state: .texas),
    USCity("San Diego", state: .california),
    USCity("Dallas", state: .texas),
    USCity("San Jose", state: .california),
    USCity("Jacksonville", state: .florida),
    USCity("Fort Worth", state: .texas),
    USCity("El Paso", state: .texas),
    USCity("Detroit", state: .michigan),
    USCity("Memphis", state: .tennessee),
    USCity("Portland", state: .oregon),
    USCity("Louisville", state: .kentucky),
    USCity("Baltimore", state: .maryland),
    USCity("Milwaukee", state: .wisconsin),
    USCity("Albuquerque", state: .newMexico),
    USCity("Tucson", state: .arizona),
    USCity("Fresno", state: .california),
    USCity("Mesa", state: .arizona),
    USCity("Kansas City", state: .missouri),
    USCity("Miami", state: .florida),
    USCity("Long Beach", state: .california),
    USCity("Virginia Beach", state: .virginia),
    USCity("Oakland", state: .california),
    USCity("Minneapolis", state: .minnesota),
    USCity("Tampa", state: .florida),
    USCity("Tulsa", state: .oklahoma),
    USCity("Arlington", state: .texas),
    USCity("New Orleans", state: .louisiana),
    USCity("Wichita", state: .kansas),
    USCity("Cleveland", state: .ohio),
    USCity("Bakersfield", state: .california),
    USCity("Aurora", state: .colorado),
    USCity("Anaheim", state: .california),
    USCity("Santa Ana", state: .california),
    USCity("Riverside", state: .california),
    USCity("Corpus Christi", state: .texas),
    USCity("Stockton", state: .california),
    USCity("Pittsburgh", state: .pennsylvania),
    USCity("Cincinnati", state: .ohio),
    USCity("St. Louis", state: .missouri),
    USCity("Orlando", state: .florida),
    USCity("Newark", state: .newJersey),
    USCity("Greensboro", state: .northCarolina),
    USCity("Jersey City", state: .newJersey),
    USCity("Laredo", state: .texas),
    USCity("Scottsdale", state: .arizona),
    USCity("Seattle", state: .washington),
  ]
  /// More familiar cities and rare initial letters; verified against the 2025 Census Gazetteer.
  public static let explorationCities: [USCity] = [
    USCity("Akron", state: .ohio),
    USCity("Allentown", state: .pennsylvania),
    USCity("Anchorage", state: .alaska),
    USCity("Bend", state: .oregon),
    USCity("Billings", state: .montana),
    USCity("Boulder", state: .colorado),
    USCity("Charlotte", state: .northCarolina),
    USCity("Chattanooga", state: .tennessee),
    USCity("Colorado Springs", state: .colorado),
    USCity("Dayton", state: .ohio),
    USCity("Durham", state: .northCarolina),
    USCity("Erie", state: .pennsylvania),
    USCity("Eugene", state: .oregon),
    USCity("Fairbanks", state: .alaska),
    USCity("Fargo", state: .northDakota),
    USCity("Fort Collins", state: .colorado),
    USCity("Huntsville", state: .alabama),
    USCity("Ithaca", state: .newYork),
    USCity("Knoxville", state: .tennessee),
    USCity("Las Vegas", state: .nevada),
    USCity("Medford", state: .oregon),
    USCity("Missoula", state: .montana),
    USCity("Ogden", state: .utah),
    USCity("Pasadena", state: .california),
    USCity("Philadelphia", state: .pennsylvania),
    USCity("Provo", state: .utah),
    USCity("Quincy", state: .massachusetts),
    USCity("Reno", state: .nevada),
    USCity("Rochester", state: .newYork),
    USCity("San Francisco", state: .california),
    USCity("Santa Barbara", state: .california),
    USCity("Santa Monica", state: .california),
    USCity("Savannah", state: .georgia),
    USCity("Sioux Falls", state: .southDakota),
    USCity("Spokane", state: .washington),
    USCity("Tacoma", state: .washington),
    USCity("Toledo", state: .ohio),
    USCity("Urbana", state: .illinois),
    USCity("Utica", state: .newYork),
    USCity("Vancouver", state: .washington),
    USCity("Xenia", state: .ohio),
    USCity("Yakima", state: .washington),
    USCity("Yonkers", state: .newYork),
    USCity("York", state: .pennsylvania),
    USCity("Youngstown", state: .ohio),
    USCity("Ypsilanti", state: .michigan),
    USCity("Yreka", state: .california),
    USCity("Yuma", state: .arizona),
    USCity("Zanesville", state: .ohio),
    USCity("Zephyrhills", state: .florida),
  ]

}

private struct CatalogDeduplicationContext {
  let city: USCity
  let seenCityIDs: Set<String>
}
