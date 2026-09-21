import Foundation
import SpecificationCore
import SwiftDecision

/// Public, read-only state suitable for presenting a game in a UI.
public struct CityGameSnapshot: Sendable, Equatable {
  public let usedCities: [USCity]
  public let requiredStartingLetter: Character?
  public let ending: CityGameEnding?
  public let isSubmissionInProgress: Bool

  public var isFinished: Bool { ending != nil }
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
  private var usedCities: [USCity] = []
  private var usedCityIDs = Set<String>()
  private var requiredStartingLetter: Character?
  private var ending: CityGameEnding?
  private var isSubmissionInProgress = false

  public init(decisions: DecisionEngine, catalog: USCityCatalog = .standard) {
    self.decisions = decisions
    self.catalog = catalog
  }

  public func snapshot() -> CityGameSnapshot {
    CityGameSnapshot(
      usedCities: usedCities,
      requiredStartingLetter: requiredStartingLetter,
      ending: ending,
      isSubmissionInProgress: isSubmissionInProgress
    )
  }

  /// Validates a free-form city name and, when possible, asks the model for the computer's reply.
  public func submit(_ rawCity: String) async throws -> CityGameTurnResult {
    guard ending == nil else { return .gameAlreadyFinished }
    guard !isSubmissionInProgress else { return .submissionInProgress }
    isSubmissionInProgress = true
    defer { isSubmissionInProgress = false }

    let playerCity = USCity(rawCity)
    let context = PlayerSubmissionContext(
      city: playerCity,
      requiredStartingLetter: requiredStartingLetter,
      usedCityIDs: usedCityIDs
    )
    let preflight = try await Self.preflightRouter().decide(context)
    switch preflight {
    case .rejected(let rejection):
      return .rejected(rejection)
    case .noChainableLetters:
      return .rejected(.cityNameHasNoLatinLetters)
    case .wrongStartingLetter:
      guard let expected = context.requiredStartingLetter else {
        assertionFailure("A wrong-letter route requires a current letter.")
        return .rejected(.emptyInput)
      }
      return .rejected(.wrongStartingLetter(expected: expected, actual: playerCity.firstLetter))
    case .alreadyUsed:
      return .rejected(.alreadyUsed(playerCity))
    case .ready:
      break
    case nil:
      assertionFailure("The preflight router always has a fallback.")
      return .rejected(.emptyInput)
    }

    let validation = try await decisions.noul(
      statement:
        "Is the named place a real city located in the United States? Answer true only when the place is a US city.",
      context: "City name entered by the player: \(playerCity.name)"
    )
    switch validation.outcome {
    case .accepted(true):
      break
    case .accepted(false):
      return .cityNotRecognized(playerCity)
    case .abstained(let reason):
      return .cityVerificationAbstained(playerCity, reason: reason)
    case .fallback(_, let reason):
      return .cityVerificationFallback(playerCity, reason: reason)
    }

    guard let nextLetter = playerCity.lastLetter else {
      return .rejected(.emptyInput)
    }
    let candidateContext = ReplyCandidateContext(
      requiredStartingLetter: nextLetter,
      usedCityIDs: usedCityIDs.union([playerCity.id])
    )
    let candidates = try await replyCandidates(for: candidateContext)
    let plan = try await Self.replyPlanRouter().decide(
      ReplyPlanContext(
        candidates: candidates,
        requiredStartingLetter: nextLetter
      ))

    switch plan {
    case .noAvailableReply:
      commit(playerCity)
      ending = .noAvailableReply(startingLetter: nextLetter)
      requiredStartingLetter = nextLetter
      return .playerWonNoAvailableReply(playerCity: playerCity, startingLetter: nextLetter)

    case .onlyAvailableCity:
      guard let computerCity = candidates.first else {
        assertionFailure("The single-city route requires a candidate.")
        return .playerWonNoAvailableReply(playerCity: playerCity, startingLetter: nextLetter)
      }
      commit(playerCity)
      commit(computerCity)
      requiredStartingLetter = computerCity.lastLetter
      return .computerReplied(
        playerCity: playerCity,
        computerCity: computerCity,
        selection: .onlyAvailableCity
      )

    case .askModel:
      let options = Array(candidates.prefix(5))
      let result = try await decisions.choice(
        instructions:
          "Choose the strongest legal next US city for a city-chain game. Select only from the provided options. Prefer a familiar, unambiguous city name.",
        context:
          "The previous city was \(playerCity.name). Your city must start with \(nextLetter). Already-used cities are excluded.",
        options: options.map { ChoiceOption(label: $0, description: $0.name) }
      )

      switch result.outcome {
      case .accepted(let computerCity):
        commit(playerCity)
        commit(computerCity)
        requiredStartingLetter = computerCity.lastLetter
        return .computerReplied(
          playerCity: playerCity,
          computerCity: computerCity,
          selection: .acceptedByDecision(confidence: result.confidence)
        )

      case .fallback(let computerCity, let reason):
        commit(playerCity)
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

  private func commit(_ city: USCity) {
    usedCityIDs.insert(city.id)
    usedCities.append(city)
  }

  private func replyCandidates(for context: ReplyCandidateContext) async throws -> [USCity] {
    let startsWithRequiredLetter = AnyAsyncSpecification<ReplyCandidate> { candidate in
      candidate.city.firstLetter == candidate.requiredStartingLetter
    }
    let hasNotBeenUsed = AnyAsyncSpecification<ReplyCandidate> { candidate in
      !candidate.usedCityIDs.contains(candidate.city.id)
    }
    let isEligible = startsWithRequiredLetter.andAsync(hasNotBeenUsed)

    var candidates: [USCity] = []
    for city in catalog.cities {
      let candidate = ReplyCandidate(
        city: city,
        requiredStartingLetter: context.requiredStartingLetter,
        usedCityIDs: context.usedCityIDs
      )
      if try await isEligible.isSatisfiedBy(candidate) {
        candidates.append(city)
        if candidates.count == 5 { break }
      }
    }
    return candidates
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

private struct ReplyCandidateContext: Sendable {
  let requiredStartingLetter: Character
  let usedCityIDs: Set<String>
}

private struct ReplyCandidate: Sendable {
  let city: USCity
  let requiredStartingLetter: Character
  let usedCityIDs: Set<String>
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
