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
  public let letterContinuations: [CityLetterContinuation]

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
  private let continuationPolicy: CityContinuationPolicy
  private var letterContinuations: [CityLetterContinuation] = []
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
  ///   - continuationPolicy: Strict last-letter chaining or a child-friendly search through previous letters.
  ///   - randomCandidateIndex: An index selector used only when Choice inference throws.
  public init(
    decisions: DecisionEngine,
    catalog: USCityCatalog = .standard,
    continuationPolicy: CityContinuationPolicy = .lastLetter,
    randomCandidateIndex: @escaping @Sendable (Range<Int>) -> Int = { Int.random(in: $0) }
  ) {
    self.decisions = decisions
    self.catalog = catalog
    self.continuationPolicy = continuationPolicy
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
      validationSource: validationSource,
      letterContinuations: letterContinuations
    )
  }

  /// Starts a fresh round when there is no turn in progress.
  public func reset() {
    guard !isSubmissionInProgress else { return }
    usedCities.removeAll(keepingCapacity: true)
    letterContinuations.removeAll(keepingCapacity: true)
    usedCityIDs.removeAll(keepingCapacity: true)
    requiredStartingLetter = nil
    ending = nil
    consecutiveMistakes = 0
    cityHint = nil
    validationSource = nil
  }

  /// Validates a free-form city name and, when possible, asks the model for the computer's reply.
  public func submit(_ rawCity: String) async throws -> CityGameTurnResult {
    try await submitWithTrace(rawCity).result
  }

  /// Evaluates one turn and returns the result with its curated engine trace.
  public func submitWithTrace(_ rawCity: String) async throws -> CityGameTracedTurnResult {
    var pipeline: [CityGamePipelineStage] = []
    func finish(_ result: CityGameTurnResult) -> CityGameTracedTurnResult {
      CityGameTracedTurnResult(result: result, pipeline: pipeline)
    }

    guard ending == nil else {
      pipeline.append(
        CityGameTraceProjection.stage(
          id: "game-state", title: "Game state", summary: "The round has already ended."))
      return finish(.gameAlreadyFinished)
    }
    guard !isSubmissionInProgress else {
      pipeline.append(
        CityGameTraceProjection.stage(
          id: "submission-state", title: "Submission state", summary: "Another turn is in progress."
        ))
      return finish(.submissionInProgress)
    }
    isSubmissionInProgress = true
    defer { isSubmissionInProgress = false }

    var playerCity = USCity(rawCity)
    let context = PlayerSubmissionContext(
      city: playerCity,
      requiredStartingLetter: requiredStartingLetter,
      usedCityIDs: usedCityIDs
    )
    let preflightRecorder = SpecificationTraceRecorder()
    let preflightSpecification = Self.preflightRouter().tracedAsync("city.player-preflight")
    let preflight = try await SpecificationTraceRuntime.decideAsync(
      preflightSpecification,
      context,
      recordingTo: preflightRecorder)
    pipeline.append(
      CityGameTraceProjection.specificationStage(
        id: "player-preflight", title: "Player city checks",
        summary: Self.preflightSummary(preflight), events: preflightRecorder.events))
    switch preflight {
    case .rejected(let rejection):
      return finish(try await recordMistake(.rejected(rejection)))
    case .noChainableLetters:
      return finish(try await recordMistake(.rejected(.cityNameHasNoLatinLetters)))
    case .wrongStartingLetter:
      guard let expected = context.requiredStartingLetter else {
        assertionFailure("A wrong-letter route requires a current letter.")
        return finish(.rejected(.emptyInput))
      }
      return finish(
        try await recordMistake(
          .rejected(.wrongStartingLetter(expected: expected, actual: playerCity.firstLetter))))
    case .alreadyUsed:
      return finish(try await recordMistake(.rejected(.alreadyUsed(playerCity))))
    case .ready:
      break
    case nil:
      assertionFailure("The preflight router always has a fallback.")
      return finish(.rejected(.emptyInput))
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
      pipeline.append(
        CityGameTraceProjection.stage(
          id: "city-validation", title: "City validation",
          summary: "SwiftDecision failed: \(String(reflecting: type(of: error)))."))
      let catalogRecorder = SpecificationTraceRecorder()
      let catalogCity = try await catalogMatch(for: playerCity, recordingTo: catalogRecorder)
      pipeline.append(
        CityGameTraceProjection.specificationStage(
          id: "catalog-validation", title: "Local atlas check",
          summary: catalogCity == nil ? "No matching catalog city." : "Matched a catalog city.",
          events: catalogRecorder.events))
      guard let catalogCity else { throw error }
      playerCity = catalogCity
      validation = nil
      validationSource = .localCatalogFallback
    }

    if let validation {
      pipeline.append(
        CityGameTraceProjection.decisionStage(
          id: "city-validation", title: "City validation",
          summary: Self.decisionSummary(validation.outcome),
          details: [
            CityGameTraceDetail(
              id: "city-recognized", label: "Recognized by Jev",
              value: validation.value.map { $0 ? "Yes" : "No" } ?? "Unknown")
          ], result: validation))
      switch validation.outcome {
      case .accepted(true):
        let catalogRecorder = SpecificationTraceRecorder()
        let catalogCity = try await catalogMatch(for: playerCity, recordingTo: catalogRecorder)
        pipeline.append(
          CityGameTraceProjection.specificationStage(
            id: "catalog-validation", title: "Local atlas check",
            summary: catalogCity == nil ? "No matching catalog city." : "Matched a catalog city.",
            events: catalogRecorder.events))
        if let catalogCity {
          playerCity = catalogCity
        }
      case .accepted(false):
        return finish(try await recordMistake(.cityNotRecognized(playerCity)))
      case .abstained(let reason):
        let catalogRecorder = SpecificationTraceRecorder()
        let catalogCity = try await catalogMatch(for: playerCity, recordingTo: catalogRecorder)
        pipeline.append(
          CityGameTraceProjection.specificationStage(
            id: "catalog-validation", title: "Local atlas check",
            summary: catalogCity == nil ? "No matching catalog city." : "Matched a catalog city.",
            events: catalogRecorder.events))
        guard let catalogCity else {
          return finish(.cityVerificationAbstained(playerCity, reason: reason))
        }
        playerCity = catalogCity
        validationSource = .localCatalogFallback
      case .fallback(_, let reason):
        let catalogRecorder = SpecificationTraceRecorder()
        let catalogCity = try await catalogMatch(for: playerCity, recordingTo: catalogRecorder)
        pipeline.append(
          CityGameTraceProjection.specificationStage(
            id: "catalog-validation", title: "Local atlas check",
            summary: catalogCity == nil ? "No matching catalog city." : "Matched a catalog city.",
            events: catalogRecorder.events))
        guard let catalogCity else {
          return finish(.cityVerificationFallback(playerCity, reason: reason))
        }
        playerCity = catalogCity
        validationSource = .localCatalogFallback
      }
    }

    guard let nextLetter = playerCity.lastLetter else {
      return finish(.rejected(.emptyInput))
    }
    let continuationRecorder = SpecificationTraceRecorder()
    let replyContinuation = continuation(
      after: playerCity, excluding: usedCityIDs.union([playerCity.id]),
      recordingTo: continuationRecorder)
    pipeline.append(
      CityGameTraceProjection.specificationStage(
        id: "player-continuation", title: "Next letter",
        summary:
          "The computer needs a city starting with \(replyContinuation.startingLetter ?? nextLetter).",
        details: [
          CityGameTraceDetail(
            id: "skipped-letters", label: "Skipped letters",
            value: replyContinuation.skippedLetters.map(String.init).joined(separator: ", "))
        ], events: continuationRecorder.events))
    let candidatesRecorder = SpecificationTraceRecorder()
    let candidates = Array(
      try await tracedAvailableCities(
        requiredStartingLetter: replyContinuation.startingLetter,
        usedCityIDs: usedCityIDs.union([playerCity.id]),
        recordingTo: candidatesRecorder
      ).prefix(5))
    pipeline.append(
      CityGameTraceProjection.specificationStage(
        id: "reply-candidates", title: "Available replies",
        summary:
          "Found \(candidates.count) candidate\(candidates.count == 1 ? "" : "s") for the model.",
        events: candidatesRecorder.events))

    let replyPlanRecorder = SpecificationTraceRecorder()
    let replyPlanSpecification = Self.replyPlanRouter().tracedAsync("city.reply-plan")
    let plan = try await SpecificationTraceRuntime.decideAsync(
      replyPlanSpecification,
      ReplyPlanContext(
        candidates: candidates,
        requiredStartingLetter: nextLetter
      ), recordingTo: replyPlanRecorder)
    pipeline.append(
      CityGameTraceProjection.specificationStage(
        id: "reply-plan", title: "Reply plan",
        summary: Self.replyPlanSummary(plan), events: replyPlanRecorder.events))

    switch plan {
    case .noAvailableReply:
      commitPlayer(playerCity, source: validationSource, continuation: replyContinuation)
      ending = .noAvailableReply(startingLetter: nextLetter)
      requiredStartingLetter = nextLetter
      pipeline.append(
        CityGameTraceProjection.stage(
          id: "turn-commit", title: "Route update", summary: "The player's city ends the round."))
      return finish(.playerWonNoAvailableReply(playerCity: playerCity, startingLetter: nextLetter))

    case .onlyAvailableCity:
      guard let computerCity = candidates.first else {
        assertionFailure("The single-city route requires a candidate.")
        return finish(
          .playerWonNoAvailableReply(playerCity: playerCity, startingLetter: nextLetter))
      }
      commitPlayer(playerCity, source: validationSource, continuation: replyContinuation)
      commit(computerCity)
      pipeline.append(
        CityGameTraceProjection.stage(
          id: "turn-commit", title: "Route update", summary: "Both cities were added to the route.")
      )
      let nextTurnEvents = prepareNextTurn(after: computerCity)
      pipeline.append(
        CityGameTraceProjection.specificationStage(
          id: "computer-continuation", title: "Next player letter",
          summary: requiredStartingLetter.map { "The next city starts with \($0)." }
            ?? "Any starting letter is allowed.", events: nextTurnEvents))
      return finish(
        .computerReplied(
          playerCity: playerCity,
          computerCity: computerCity,
          selection: .onlyAvailableCity
        ))

    case .askModel:
      let options = Array(candidates.prefix(5))
      let startingRule =
        replyContinuation.startingLetter.map { "Your city must start with \($0)." }
        ?? "All letters of the previous name are exhausted; any starting letter is allowed."
      let result: DecisionResult<USCity>
      do {
        result = try await decisions.choice(
          instructions:
            "Choose the strongest legal next US city for a city-chain game. Select only from the provided options. Prefer a familiar, unambiguous city name.",
          context:
            "The previous city was \(playerCity.name). \(startingRule) Already-used cities are excluded.",
          options: options.map { ChoiceOption(label: $0, description: $0.name) }
        )
      } catch {
        if error is CancellationError {
          throw error
        }
        try Task.checkCancellation()
        pipeline.append(
          CityGameTraceProjection.stage(
            id: "computer-choice", title: "Computer city choice",
            summary:
              "SwiftDecision failed: \(String(reflecting: type(of: error))); using a random legal candidate."
          ))

        let requestedIndex = randomCandidateIndex(options.indices)
        let selectedIndex =
          options.indices.contains(requestedIndex)
          ? requestedIndex
          : options.startIndex
        let computerCity = options[selectedIndex]
        commitPlayer(playerCity, source: validationSource, continuation: replyContinuation)
        commit(computerCity)
        pipeline.append(
          CityGameTraceProjection.stage(
            id: "turn-commit", title: "Route update",
            summary: "Both cities were added to the route."))
        let nextTurnEvents = prepareNextTurn(after: computerCity)
        pipeline.append(
          CityGameTraceProjection.specificationStage(
            id: "computer-continuation", title: "Next player letter",
            summary: requiredStartingLetter.map { "The next city starts with \($0)." }
              ?? "Any starting letter is allowed.", events: nextTurnEvents))
        return finish(
          .computerReplied(
            playerCity: playerCity,
            computerCity: computerCity,
            selection: .randomFallback
          ))
      }

      pipeline.append(
        CityGameTraceProjection.decisionStage(
          id: "computer-choice", title: "Computer city choice",
          summary: Self.decisionSummary(result.outcome),
          details: [
            CityGameTraceDetail(
              id: "candidate-count", label: "Candidates", value: String(options.count)),
            CityGameTraceDetail(
              id: "selected-city", label: "Selected city", value: result.value?.name ?? "None"),
            CityGameTraceDetail(
              id: "confidence", label: "Confidence",
              value: "\(Int((result.confidence * 100).rounded()))%"),
          ], result: result))
      switch result.outcome {
      case .accepted(let computerCity):
        commitPlayer(playerCity, source: validationSource, continuation: replyContinuation)
        commit(computerCity)
        pipeline.append(
          CityGameTraceProjection.stage(
            id: "turn-commit", title: "Route update",
            summary: "Both cities were added to the route."))
        let nextTurnEvents = prepareNextTurn(after: computerCity)
        pipeline.append(
          CityGameTraceProjection.specificationStage(
            id: "computer-continuation", title: "Next player letter",
            summary: requiredStartingLetter.map { "The next city starts with \($0)." }
              ?? "Any starting letter is allowed.", events: nextTurnEvents))
        return finish(
          .computerReplied(
            playerCity: playerCity,
            computerCity: computerCity,
            selection: .acceptedByDecision(confidence: result.confidence)
          ))

      case .fallback(let computerCity, let reason):
        commitPlayer(playerCity, source: validationSource, continuation: replyContinuation)
        commit(computerCity)
        pipeline.append(
          CityGameTraceProjection.stage(
            id: "turn-commit", title: "Route update",
            summary: "Both cities were added to the route."))
        let nextTurnEvents = prepareNextTurn(after: computerCity)
        pipeline.append(
          CityGameTraceProjection.specificationStage(
            id: "computer-continuation", title: "Next player letter",
            summary: requiredStartingLetter.map { "The next city starts with \($0)." }
              ?? "Any starting letter is allowed.", events: nextTurnEvents))
        return finish(
          .computerReplied(
            playerCity: playerCity,
            computerCity: computerCity,
            selection: .fallbackByDecision(confidence: result.confidence, reason: reason)
          ))

      case .abstained(let reason):
        commitPlayer(playerCity, source: validationSource, continuation: replyContinuation)
        requiredStartingLetter = nextLetter
        ending = .computerAbstained(reason: reason)
        pipeline.append(
          CityGameTraceProjection.stage(
            id: "turn-commit", title: "Route update",
            summary: "The player city was added; the computer abstained."))
        return finish(.playerWonBecauseComputerAbstained(playerCity: playerCity, reason: reason))
      }
    case nil:
      assertionFailure("The reply-plan router always has a fallback.")
      return finish(.playerWonNoAvailableReply(playerCity: playerCity, startingLetter: nextLetter))
    }
  }

  private func continuation(
    after city: USCity,
    excluding usedIDs: Set<String>,
    recordingTo recorder: SpecificationTraceRecorder
  ) -> CityLetterContinuation {
    let rule = CityContinuationSpec(policy: continuationPolicy).traced("city.letter-continuation")
    guard
      let result = SpecificationTraceRuntime.decide(
        rule,
        CityContinuationContext(city: city, catalog: catalog.cities, usedCityIDs: usedIDs),
        recordingTo: recorder)
    else {
      preconditionFailure("A validated city must contain chainable letters.")
    }
    return result
  }

  private func prepareNextTurn(after city: USCity) -> [SpecificationTraceEvent] {
    let recorder = SpecificationTraceRecorder()
    let next = continuation(after: city, excluding: usedCityIDs, recordingTo: recorder)
    letterContinuations.append(next)
    requiredStartingLetter = next.startingLetter
    return recorder.events
  }

  private func commitPlayer(
    _ city: USCity, source: CityValidationSource, continuation: CityLetterContinuation
  ) {
    consecutiveMistakes = 0
    cityHint = nil
    validationSource = source
    letterContinuations.append(continuation)
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

  private func catalogMatch(
    for city: USCity,
    recordingTo recorder: SpecificationTraceRecorder
  ) async throws -> USCity? {
    let lookup = AnyAsyncDecisionSpec<CatalogMatchContext, USCity> { context in
      for candidate in context.candidates where candidate.id == context.city.id {
        return candidate
      }
      return nil
    }.tracedAsync("city.catalog-match")
    return try await SpecificationTraceRuntime.decideAsync(
      lookup,
      CatalogMatchContext(city: city, candidates: catalog.cities),
      recordingTo: recorder)
  }

  private func tracedAvailableCities(
    requiredStartingLetter: Character?,
    usedCityIDs: Set<String>,
    recordingTo recorder: SpecificationTraceRecorder
  ) async throws -> [USCity] {
    let search = AvailableCitySearchDecision(cities: catalog.cities)
    return try await SpecificationTraceRuntime.decideAsync(
      search,
      ReplySearchContext(requiredStartingLetter: requiredStartingLetter, usedCityIDs: usedCityIDs),
      recordingTo: recorder) ?? []
  }

  private func orderedAvailableCities(
    requiredStartingLetter: Character?,
    usedCityIDs: Set<String>
  ) async throws -> [USCity] {
    try await Self.orderedAvailableCities(
      in: catalog.cities,
      requiredStartingLetter: requiredStartingLetter,
      usedCityIDs: usedCityIDs)
  }

  private static func orderedAvailableCities(
    in cities: [USCity],
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
    for (catalogIndex, city) in cities.enumerated() {
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

  private struct AvailableCitySearchDecision: AsyncDecisionSpec, Sendable {
    let cities: [USCity]

    func decide(_ context: ReplySearchContext) async throws -> [USCity]? {
      try await SpecificationTraceRuntime.withDecision("city.available-replies") {
        try await SpecificationTraceRuntime.withoutRecording {
          try await CityChainGame.orderedAvailableCities(
            in: cities,
            requiredStartingLetter: context.requiredStartingLetter,
            usedCityIDs: context.usedCityIDs)
        }
      }
    }
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

  private static func preflightSummary(_ result: PreflightResult?) -> String {
    switch result {
    case .rejected: "Rejected by a player input rule."
    case .noChainableLetters: "The city has no usable Latin letters."
    case .wrongStartingLetter: "The city does not start with the required letter."
    case .alreadyUsed: "The city is already in the route."
    case .ready: "Player input passed the local rules."
    case nil: "No preflight rule selected a result."
    }
  }

  private static func replyPlanSummary(_ result: ReplyPlan?) -> String {
    switch result {
    case .noAvailableReply: "No unused city matches the required letter."
    case .onlyAvailableCity: "Exactly one legal reply is available."
    case .askModel: "Several legal replies are available; ask SwiftDecision to choose."
    case nil: "No reply plan selected."
    }
  }

  private static func decisionSummary<Value: Sendable>(_ outcome: DecisionOutcome<Value>) -> String
  {
    switch outcome {
    case .accepted: "Accepted by the selected policy."
    case .fallback: "Used the configured fallback."
    case .abstained: "Decision abstained."
    }
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
  let candidates: [USCity]
}

private struct ReplySearchContext: Sendable {
  let requiredStartingLetter: Character?
  let usedCityIDs: Set<String>
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
