import CityChainGame
import Foundation

/// One short, curated fact Scout can share about a city or its state.
struct ScoutFact: Codable, Identifiable, Sendable {
  let id: String
  let stateCode: String?
  let cityID: String?
  let text: String
  let sourceTitle: String
  let sourceURL: URL
  let verifiedOn: String?

  private enum CodingKeys: String, CodingKey {
    case id
    case stateCode
    case cityID
    case text
    case sourceTitle
    case sourceURL
    case verifiedOn
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    stateCode = try values.decodeIfPresent(String.self, forKey: .stateCode)
    cityID = try values.decodeIfPresent(String.self, forKey: .cityID)
    text = try values.decode(String.self, forKey: .text)
    sourceTitle = try values.decode(String.self, forKey: .sourceTitle)
    verifiedOn = try values.decodeIfPresent(String.self, forKey: .verifiedOn)

    let sourceString = try values.decode(String.self, forKey: .sourceURL)
    guard
      let sourceURL = URL(string: sourceString),
      sourceURL.scheme?.lowercased() == "https",
      sourceURL.host != nil
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .sourceURL, in: values, debugDescription: "Fact source must be an HTTPS URL.")
    }
    self.sourceURL = sourceURL

    guard !id.isEmpty, !text.isEmpty, !sourceTitle.isEmpty else {
      throw DecodingError.dataCorruptedError(
        forKey: .id, in: values, debugDescription: "Fact ID, text, and source title must be present.")
    }
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encodeIfPresent(stateCode, forKey: .stateCode)
    try values.encodeIfPresent(cityID, forKey: .cityID)
    try values.encode(text, forKey: .text)
    try values.encode(sourceTitle, forKey: .sourceTitle)
    try values.encode(sourceURL.absoluteString, forKey: .sourceURL)
    try values.encodeIfPresent(verifiedOn, forKey: .verifiedOn)
  }
}

/// The offline, curated fact catalog bundled with City Chain.
struct ScoutFactCatalog: Codable, Sendable {
  let facts: [ScoutFact]

  init(facts: [ScoutFact]) {
    self.facts = facts
  }

  init(from decoder: Decoder) throws {
    facts = try decoder.singleValueContainer().decode([ScoutFact].self)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(facts)
  }

  static func bundled(bundle: Bundle = .main) -> Self? {
    guard let url = bundle.url(forResource: "state-facts-v1", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let catalog = try? JSONDecoder().decode(Self.self, from: data),
          !catalog.facts.isEmpty
    else {
      return nil
    }
    return catalog
  }
}

/// Remembers shown facts across launches. Gameplay avoids repeats until the
/// catalog is exhausted; atlas browsing repeats locally when needed to stay relevant.
@MainActor
final class ScoutFactSelectionStore {
  private let catalog: ScoutFactCatalog?
  private let defaults: UserDefaults
  private let storageKey: String

  init(
    catalog: ScoutFactCatalog? = .bundled(),
    defaults: UserDefaults = .standard,
    storageKey: String = "com.soundblaster.citychain.scout-seen-fact-ids"
  ) {
    self.catalog = catalog
    self.defaults = defaults
    self.storageKey = storageKey
  }

  func nextFact(for city: USCity) -> ScoutFact? {
    selectFact(for: city, locationOnly: false)
  }

  /// Atlas selections must describe the selected place, even when its facts
  /// have already appeared. This shares the game's persistent history.
  func nextLocationFact(for city: USCity) -> ScoutFact? {
    selectFact(for: city, locationOnly: true)
  }

  private func selectFact(for city: USCity, locationOnly: Bool) -> ScoutFact? {
    guard let catalog, !catalog.facts.isEmpty else { return nil }

    let allIDs = Set(catalog.facts.map(\.id))
    var seenIDs = Set(defaults.stringArray(forKey: storageKey) ?? [])
    seenIDs.formIntersection(allIDs)
    if seenIDs.count == allIDs.count {
      seenIDs.removeAll()
    }

    let cityFacts = catalog.facts.filter { $0.cityID == city.id }
    let stateFacts = catalog.facts.filter {
      guard let state = city.stateAbbreviation, let factState = $0.stateCode else { return false }
      return factState.uppercased() == state.uppercased()
    }
    let unseenCityFacts = cityFacts.filter { !seenIDs.contains($0.id) }
    let unseenStateFacts = stateFacts.filter { !seenIDs.contains($0.id) }
    let fallbackFacts = locationOnly
      ? (cityFacts.isEmpty ? stateFacts : cityFacts)
      : catalog.facts.filter { !seenIDs.contains($0.id) }
    let selected = unseenCityFacts.randomElement()
      ?? unseenStateFacts.randomElement() ?? fallbackFacts.randomElement()
    guard let selected else { return nil }

    seenIDs.insert(selected.id)
    defaults.set(seenIDs.sorted(), forKey: storageKey)
    return selected
  }
}
