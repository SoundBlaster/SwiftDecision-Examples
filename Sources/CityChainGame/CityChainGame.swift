import Foundation
import SpecificationCore
import SwiftDecision

/// Public, read-only state suitable for presenting a game in a UI.
public struct CityGameSnapshot: Sendable, Equatable {
  public let usedCities: [USCity]
  public let requiredStartingLetter: Character?
  public let ending: CityGameEnding?
  public let isSubmissionInProgress: Bool
  public let consecutiveMistakes: Int
  public let cityHint: CityHint?
  public let validationSource: CityValidationSource?

  public var isFinished: Bool { ending != nil }
}

public struct CityHint: Sendable, Equatable {
  public let maskedName: String
  public let startingLetter: Character?
}

public enum CityValidationSource: Sendable, Equatable {
  case noul
  case localCatalogFallback
}

public enum CityGameEnding: Sendable, Equatable {
  case noAvailableReply(startingLetter: Character)
  case computerAbstained(reason: String)
}

public enum CitySubmissionRejection: Sendable, Equatable {
  case emptyInput
  case cityNameHasNoLatinLetters
  case wrongStartingLetter(expected: Character, actual: Character?)
  case alreadyUsed(USCity)
}

public enum ComputerSelection: Sendable, Equatable {
  case onlyAvailableCity
  case acceptedByDecision(confidence: Double)
  case fallbackByDecision(confidence: Double, reason: String)
  case randomFallback
}

/// The outcome of one player submission. Decision abstention and fallback remain explicit.
public enum CityGameTurnResult: Sendable, Equatable {
  case rejected(CitySubmissionRejection)
  case cityNotRecognized(USCity)
  case cityVerificationAbstained(USCity, reason: String)
  case cityVerificationFallback(USCity, reason: String)
  case computerReplied(playerCity: USCity, computerCity: USCity, selection: ComputerSelection)
  case playerWonNoAvailableReply(playerCity: USCity, startingLetter: Character)
  case playerWonBecauseComputerAbstained(playerCity: USCity, reason: String)
  case submissionInProgress
  case gameAlreadyFinished
}

/// A rule-driven city-chain engine. Core specifications own eligibility, filtering, and routing;
/// SwiftDecision validates the player's city and selects among up to five computer replies.
public actor CityChainGame {
  private let decisions: DecisionEngine
  private let catalog: USCityCatalog
  /// Chooses from the deterministic reply candidates if Choice inference fails.
  private let randomCandidateIndex: @Sendable (Range<Int>) -> Int
  private var usedCities: [USCity] = []
  private var usedCityIDs = Set<String>()
  private var requiredStartingLetter: Character?
  private var ending: CityGameEnding?
  private var isSubmissionInProgress = false
  private var consecutiveMistakes = 0
  private var cityHint: CityHint?
  private var validationSource: CityValidationSource?

  /// Creates a game. Choice failures fall back to a random candidate from the ordered first five.
  ///
  /// - Parameters:
  ///   - decisions: The engine used to validate the player's city and rank computer replies.
  ///   - catalog: Ordered cities eligible as computer replies.
  ///   - randomCandidateIndex: An index selector used only when Choice inference throws.
  public init(
    decisions: DecisionEngine,
    catalog: USCityCatalog = .standard,
    randomCandidateIndex: @escaping @Sendable (Range<Int>) -> Int = { Int.random(in: $0) }
  ) {
    self.decisions = decisions
    self.catalog = catalog
    self.randomCandidateIndex = randomCandidateIndex
  }

  public func snapshot() -> CityGameSnapshot {
    CityGameSnapshot(
      usedCities: usedCities,
      requiredStartingLetter: requiredStartingLetter,
      ending: ending,
      isSubmissionInProgress: isSubmissionInProgress,
      consecutiveMistakes: consecutiveMistakes,
      cityHint: cityHint,
      validationSource: validationSource
    )
  }

  /// Validates a free-form city name and, when possible, asks the model for the computer's reply.
  public func submit(_ rawCity: String) async throws -> CityGameTurnResult {
    guard ending == nil else { return .gameAlreadyFinished }
    guard !isSubmissionInProgress else { return .submissionInProgress }
    isSubmissionInProgress = true
    defer { isSubmissionInProgress = false }

    var playerCity = USCity(rawCity)
    let context = PlayerSubmissionContext(
      city: playerCity,
      requiredStartingLetter: requiredStartingLetter,
      usedCityIDs: usedCityIDs
    )
    let preflight = try await Self.preflightRouter().decide(context)
    switch preflight {
    case .rejected(let rejection):
      return try await recordMistake(.rejected(rejection))
    case .noChainableLetters:
      return try await recordMistake(.rejected(.cityNameHasNoLatinLetters))
    case .wrongStartingLetter:
      guard let expected = context.requiredStartingLetter else {
        assertionFailure("A wrong-letter route requires a current letter.")
        return .rejected(.emptyInput)
      }
      return try await recordMistake(
        .rejected(.wrongStartingLetter(expected: expected, actual: playerCity.firstLetter)))
    case .alreadyUsed:
      return try await recordMistake(.rejected(.alreadyUsed(playerCity)))
    case .ready:
      break
    case nil:
      assertionFailure("The preflight router always has a fallback.")
      return .rejected(.emptyInput)
    }

    var validationSource = CityValidationSource.noul
    let validation: DecisionResult<Bool>?
    do {
      validation = try await decisions.noul(
        statement:
          "Is the named place a real city located in the United States? Answer true only when the place is a US city.",
        context: "City name entered by the player: \(playerCity.name)"
      )
    } catch {
      if error is CancellationError { throw error }
      try Task.checkCancellation()
      guard let catalogCity = try await catalogMatch(for: playerCity) else { throw error }
      playerCity = catalogCity
      validation = nil
      validationSource = .localCatalogFallback
    }

    if let validation {
      switch validation.outcome {
      case .accepted(true):
        break
      case .accepted(false):
        return try await recordMistake(.cityNotRecognized(playerCity))
      case .abstained(let reason):
        guard let catalogCity = try await catalogMatch(for: playerCity) else {
          return .cityVerificationAbstained(playerCity, reason: reason)
        }
        playerCity = catalogCity
        validationSource = .localCatalogFallback
      case .fallback(_, let reason):
        guard let catalogCity = try await catalogMatch(for: playerCity) else {
          return .cityVerificationFallback(playerCity, reason: reason)
        }
        playerCity = catalogCity
        validationSource = .localCatalogFallback
      }
    }

    guard let nextLetter = playerCity.lastLetter else {
      return .rejected(.emptyInput)
    }
    let candidates = Array(
      try await orderedAvailableCities(
        requiredStartingLetter: nextLetter,
        usedCityIDs: usedCityIDs.union([playerCity.id])
      ).prefix(5))
    let plan = try await Self.replyPlanRouter().decide(
      ReplyPlanContext(
        candidates: candidates,
        requiredStartingLetter: nextLetter
      ))

    switch plan {
    case .noAvailableReply:
      commitPlayer(playerCity, source: validationSource)
      ending = .noAvailableReply(startingLetter: nextLetter)
      requiredStartingLetter = nextLetter
      return .playerWonNoAvailableReply(playerCity: playerCity, startingLetter: nextLetter)

    case .onlyAvailableCity:
      guard let computerCity = candidates.first else {
        assertionFailure("The single-city route requires a candidate.")
        return .playerWonNoAvailableReply(playerCity: playerCity, startingLetter: nextLetter)
      }
      commitPlayer(playerCity, source: validationSource)
      commit(computerCity)
      requiredStartingLetter = computerCity.lastLetter
      return .computerReplied(
        playerCity: playerCity,
        computerCity: computerCity,
        selection: .onlyAvailableCity
      )

    case .askModel:
      let options = Array(candidates.prefix(5))
      let result: DecisionResult<USCity>
      do {
        result = try await decisions.choice(
          instructions:
            "Choose the strongest legal next US city for a city-chain game. Select only from the provided options. Prefer a familiar, unambiguous city name.",
          context:
            "The previous city was \(playerCity.name). Your city must start with \(nextLetter). Already-used cities are excluded.",
          options: options.map { ChoiceOption(label: $0, description: $0.name) }
        )
      } catch {
        if error is CancellationError {
          throw error
        }
        try Task.checkCancellation()

        let requestedIndex = randomCandidateIndex(options.indices)
        let selectedIndex =
          options.indices.contains(requestedIndex)
          ? requestedIndex
          : options.startIndex
        let computerCity = options[selectedIndex]
        commitPlayer(playerCity, source: validationSource)
        commit(computerCity)
        requiredStartingLetter = computerCity.lastLetter
        return .computerReplied(
          playerCity: playerCity,
          computerCity: computerCity,
          selection: .randomFallback
        )
      }

      switch result.outcome {
      case .accepted(let computerCity):
        commitPlayer(playerCity, source: validationSource)
        commit(computerCity)
        requiredStartingLetter = computerCity.lastLetter
        return .computerReplied(
          playerCity: playerCity,
          computerCity: computerCity,
          selection: .acceptedByDecision(confidence: result.confidence)
        )

      case .fallback(let computerCity, let reason):
        commitPlayer(playerCity, source: validationSource)
        commit(computerCity)
        requiredStartingLetter = computerCity.lastLetter
        return .computerReplied(
          playerCity: playerCity,
          computerCity: computerCity,
          selection: .fallbackByDecision(confidence: result.confidence, reason: reason)
        )

      case .abstained(let reason):
        commit(playerCity)
        requiredStartingLetter = nextLetter
        ending = .computerAbstained(reason: reason)
        return .playerWonBecauseComputerAbstained(playerCity: playerCity, reason: reason)
      }
    case nil:
      assertionFailure("The reply-plan router always has a fallback.")
      return .playerWonNoAvailableReply(playerCity: playerCity, startingLetter: nextLetter)
    }
  }

  private func commitPlayer(_ city: USCity, source: CityValidationSource) {
    consecutiveMistakes = 0
    cityHint = nil
    validationSource = source
    commit(city)
  }

  private func commit(_ city: USCity) {
    usedCityIDs.insert(city.id)
    usedCities.append(city)
  }

  private func recordMistake(_ result: CityGameTurnResult) async throws -> CityGameTurnResult {
    consecutiveMistakes += 1
    if consecutiveMistakes >= 2 {
      let available = try await orderedAvailableCities(
        requiredStartingLetter: requiredStartingLetter,
        usedCityIDs: usedCityIDs
      )
      cityHint = available.first.map(Self.makeHint)
    }
    return result
  }

  private func catalogMatch(for city: USCity) async throws -> USCity? {
    let matchesCity = AnyAsyncSpecification<CatalogMatchContext> { context in
      context.candidate.id == context.city.id
    }
    for catalogCity in catalog.cities {
      if try await matchesCity.isSatisfiedBy(
        CatalogMatchContext(city: city, candidate: catalogCity))
      {
        return catalogCity
      }
    }
    return nil
  }

  private func orderedAvailableCities(
    requiredStartingLetter: Character?,
    usedCityIDs: Set<String>
  ) async throws -> [USCity] {
    let startsWithRequiredLetter = AnyAsyncSpecification<ReplyCandidate> { candidate in
      guard let required = candidate.requiredStartingLetter else { return true }
      return candidate.city.firstLetter == required
    }
    let hasNotBeenUsed = AnyAsyncSpecification<ReplyCandidate> { candidate in
      !candidate.usedCityIDs.contains(candidate.city.id)
    }
    let isEligible = startsWithRequiredLetter.andAsync(hasNotBeenUsed)
    let appearsEarlierInCatalog = AnyAsyncSpecification<CandidateOrderContext> { pair in
      pair.left.catalogIndex < pair.right.catalogIndex
    }

    var eligible: [ReplyCandidate] = []
    for (catalogIndex, city) in catalog.cities.enumerated() {
      let candidate = ReplyCandidate(
        city: city,
        catalogIndex: catalogIndex,
        requiredStartingLetter: requiredStartingLetter,
        usedCityIDs: usedCityIDs
      )
      if try await isEligible.isSatisfiedBy(candidate) {
        eligible.append(candidate)
      }
    }

    var ordered: [ReplyCandidate] = []
    for candidate in eligible {
      var insertionIndex = ordered.endIndex
      while insertionIndex > ordered.startIndex {
        let previous = ordered[insertionIndex - 1]
        if try await appearsEarlierInCatalog.isSatisfiedBy(
          CandidateOrderContext(left: previous, right: candidate))
        {
          break
        }
        insertionIndex -= 1
      }
      ordered.insert(candidate, at: insertionIndex)
    }
    return ordered.map(\.city)
  }

  private static func makeHint(_ city: USCity) -> CityHint {
    let characters = Array(city.name)
    let letterCount = characters.reduce(into: 0) { count, character in
      if character.isLetter { count += 1 }
    }
    let reveal = AnySpecification<HintCharacterContext> { context in
      context.letterIndex < 2 || context.letterIndex >= context.letterCount - 2
    }
    var letterIndex = 0
    var maskedName = ""
    for character in characters {
      guard character.isLetter else {
        maskedName.append(character)
        continue
      }
      let context = HintCharacterContext(letterIndex: letterIndex, letterCount: letterCount)
      maskedName.append(reveal.isSatisfiedBy(context) ? character : "•")
      letterIndex += 1
    }
    return CityHint(maskedName: maskedName, startingLetter: city.firstLetter)
  }

  private static func preflightRouter() -> AsyncFirstMatchSpec<
    PlayerSubmissionContext, PreflightResult
  > {
    AsyncFirstMatchSpec<PlayerSubmissionContext, PreflightResult>.builder()
      .addPredicate({ $0.city.name.isEmpty }, result: .rejected(.emptyInput))
      .addPredicate(
        { $0.city.firstLetter == nil || $0.city.lastLetter == nil }, result: .noChainableLetters
      )
      .addPredicate(
        { context in
          guard let expected = context.requiredStartingLetter else { return false }
          return context.city.firstLetter != expected
        }, result: .wrongStartingLetter
      )
      .addPredicate(
        { context in
          context.usedCityIDs.contains(context.city.id)
        }, result: .alreadyUsed
      )
      .fallback(.ready)
      .build()
  }

  private static func replyPlanRouter() -> AsyncFirstMatchSpec<ReplyPlanContext, ReplyPlan> {
    AsyncFirstMatchSpec<ReplyPlanContext, ReplyPlan>.builder()
      .addPredicate({ $0.candidates.isEmpty }, result: .noAvailableReply)
      .addPredicate({ $0.candidates.count == 1 }, result: .onlyAvailableCity)
      .fallback(.askModel)
      .build()
  }
}

private struct PlayerSubmissionContext: Sendable {
  let city: USCity
  let requiredStartingLetter: Character?
  let usedCityIDs: Set<String>
}

private enum PreflightResult: Sendable {
  case rejected(CitySubmissionRejection)
  case noChainableLetters
  case wrongStartingLetter
  case alreadyUsed
  case ready
}

private struct ReplyCandidate: Sendable {
  let city: USCity
  let catalogIndex: Int
  let requiredStartingLetter: Character?
  let usedCityIDs: Set<String>
}

private struct CandidateOrderContext: Sendable {
  let left: ReplyCandidate
  let right: ReplyCandidate
}

private struct CatalogMatchContext: Sendable {
  let city: USCity
  let candidate: USCity
}

private struct HintCharacterContext: Sendable {
  let letterIndex: Int
  let letterCount: Int
}

private struct ReplyPlanContext: Sendable {
  let candidates: [USCity]
  let requiredStartingLetter: Character
}

private enum ReplyPlan: Sendable {
  case noAvailableReply
  case onlyAvailableCity
  case askModel
}
