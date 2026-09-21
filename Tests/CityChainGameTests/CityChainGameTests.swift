import SwiftDecision
import Testing

@testable import CityChainGame

@Suite("City-chain rules")
struct CityChainGameTests {
  @Test("The player may enter a valid city outside the computer reply catalog")
  func playerCityIsNotRestrictedToReplyCatalog() async throws {
    let backend = FixtureBackend(choiceIndex: 2)
    let game = CityChainGame(
      decisions: DecisionEngine(backend: backend),
      catalog: catalog("Dover", "Detroit", "Durham", "Duluth", "Dublin", "Dayton")
    )

    let result = try await game.submit("Riverhead")

    guard case .computerReplied(let playerCity, let computerCity, let selection) = result else {
      Issue.record("Expected a computer reply, got \(result).")
      return
    }
    #expect(playerCity == USCity("Riverhead"))
    #expect(computerCity == USCity("Durham"))
    #expect(selection == .acceptedByDecision(confidence: 0.96))

    let prompts = await backend.receivedPrompts()
    #expect(prompts.map(\.kind) == [.noul, .choice])
    #expect(
      prompts[1].options.map(\.description) == ["Dover", "Detroit", "Durham", "Duluth", "Dublin"])
    #expect(prompts[1].options.count <= 5)

    let snapshot = await game.snapshot()
    #expect(snapshot.usedCities == [USCity("Riverhead"), USCity("Durham")])
    #expect(snapshot.requiredStartingLetter == "M")
    #expect(!snapshot.isFinished)
  }

  @Test("Fast rules reject empty, wrong-letter, and reused input before calling Noul")
  func preflightRulesShortCircuitModelValidation() async throws {
    let backend = FixtureBackend()
    let game = CityChainGame(decisions: DecisionEngine(backend: backend), catalog: catalog("Dover"))

    let empty = try await game.submit(" \n ")
    #expect(empty == .rejected(.emptyInput))
    let noLatinLetters = try await game.submit("東京")
    #expect(noLatinLetters == .rejected(.cityNameHasNoLatinLetters))

    let firstTurn = try await game.submit("Riverhead")
    guard case .computerReplied = firstTurn else {
      Issue.record("Expected the one catalog city to be used as the reply.")
      return
    }

    let wrongLetter = try await game.submit("Boston")
    #expect(wrongLetter == .rejected(.wrongStartingLetter(expected: "R", actual: "B")))

    let repeatedAlias = try await game.submit(" river head ")
    guard case .rejected(.alreadyUsed(let city)) = repeatedAlias else {
      Issue.record("Expected the canonical city key to detect a repeated city.")
      return
    }
    #expect(city.id == USCity("Riverhead").id)

    let prompts = await backend.receivedPrompts()
    #expect(prompts.map(\.kind) == [.noul])
  }

  @Test("The player wins when no unused catalog city starts with the required letter")
  func noReplyEndsTheGame() async throws {
    let backend = FixtureBackend()
    let game = CityChainGame(
      decisions: DecisionEngine(backend: backend), catalog: catalog("Austin"))

    let result = try await game.submit("Bend")

    #expect(result == .playerWonNoAvailableReply(playerCity: USCity("Bend"), startingLetter: "D"))
    let prompts = await backend.receivedPrompts()
    #expect(prompts.map(\.kind) == [.noul])

    let snapshot = await game.snapshot()
    #expect(snapshot.usedCities == [USCity("Bend")])
    #expect(snapshot.ending == .noAvailableReply(startingLetter: "D"))
    #expect(snapshot.isFinished)
    #expect(try await game.submit("Detroit") == .gameAlreadyFinished)
  }

  @Test("A single legal computer reply is automatic and does not call Choice")
  func singleReplyIsSelectedWithoutInference() async throws {
    let backend = FixtureBackend()
    let game = CityChainGame(decisions: DecisionEngine(backend: backend), catalog: catalog("Dover"))

    let result = try await game.submit("Riverhead")

    #expect(
      result
        == .computerReplied(
          playerCity: USCity("Riverhead"),
          computerCity: USCity("Dover"),
          selection: .onlyAvailableCity
        ))
    let prompts = await backend.receivedPrompts()
    #expect(prompts.map(\.kind) == [.noul])
  }

  @Test("Noul rejection leaves the game state unchanged")
  func nonCityIsRejectedWithoutCommitting() async throws {
    let backend = FixtureBackend(noulAnswer: false)
    let game = CityChainGame(decisions: DecisionEngine(backend: backend), catalog: catalog("Dover"))

    let result = try await game.submit("Not A City")

    #expect(result == .cityNotRecognized(USCity("Not A City")))
    #expect(await game.snapshot().usedCities.isEmpty)
  }

  @Test("Noul abstention stays distinct from rejection")
  func uncertainCityValidationIsNotTreatedAsFalse() async throws {
    let backend = FixtureBackend(abstainNoul: true)
    let game = CityChainGame(decisions: DecisionEngine(backend: backend), catalog: catalog("Dover"))

    let result = try await game.submit("Riverhead")

    guard case .cityVerificationAbstained(USCity("Riverhead"), reason: _) = result else {
      Issue.record("Expected a distinct verification abstention, got \(result).")
      return
    }
    #expect(await game.snapshot().usedCities.isEmpty)
  }

  @Test("Choice abstention ends the game without inventing a fallback city")
  func uncertainComputerChoiceFinishesWithoutFallback() async throws {
    let backend = FixtureBackend(abstainChoice: true)
    let game = CityChainGame(
      decisions: DecisionEngine(backend: backend),
      catalog: catalog("Dover", "Detroit")
    )

    let result = try await game.submit("Riverhead")

    guard case .playerWonBecauseComputerAbstained(USCity("Riverhead"), reason: _) = result else {
      Issue.record("Expected the model abstention to remain explicit, got \(result).")
      return
    }
    let snapshot = await game.snapshot()
    #expect(snapshot.usedCities == [USCity("Riverhead")])
    #expect(snapshot.ending != nil)
  }

  @Test("An unavailable Choice backend uses a random one of the first five candidates")
  func choiceBackendFailureUsesRandomCandidateFallback() async throws {
    let backend = FixtureBackend(failChoice: true)
    let game = CityChainGame(
      decisions: DecisionEngine(backend: backend),
      catalog: catalog("Dover", "Detroit", "Durham", "Duluth", "Dublin", "Dayton"),
      randomCandidateIndex: { $0.lowerBound + 2 }
    )

    let result = try await game.submit("Riverhead")

    #expect(
      result
        == .computerReplied(
          playerCity: USCity("Riverhead"),
          computerCity: USCity("Durham"),
          selection: .randomFallback
        ))
    let prompts = await backend.receivedPrompts()
    #expect(prompts.map(\.kind) == [.noul, .choice])
    #expect(
      prompts[1].options.map(\.description) == ["Dover", "Detroit", "Durham", "Duluth", "Dublin"])
    #expect(prompts[1].options.count == 5)

    let snapshot = await game.snapshot()
    #expect(snapshot.usedCities == [USCity("Riverhead"), USCity("Durham")])
    #expect(snapshot.requiredStartingLetter == "M")
  }

  @Test("A concurrent submission cannot validate against a stale game snapshot")
  func concurrentSubmissionIsRejectedWhileInferenceIsInProgress() async throws {
    let backend = SuspendedNoulBackend()
    let game = CityChainGame(decisions: DecisionEngine(backend: backend), catalog: catalog("Dover"))
    let firstSubmission = Task { try await game.submit("Riverhead") }
    await backend.waitUntilStarted()

    #expect(await game.snapshot().isSubmissionInProgress)
    #expect(try await game.submit("Riverhead") == .submissionInProgress)

    await backend.release()
    let firstResult = try await firstSubmission.value
    guard case .computerReplied = firstResult else {
      Issue.record("Expected the original submission to finish normally.")
      return
    }
    #expect(await game.snapshot().usedCities.count == 2)
  }

  @Test("Backend errors propagate and do not commit a partial turn")
  func backendFailureLeavesStateUnchanged() async throws {
    struct FixtureFailure: Error, Sendable {}
    let backend = ClosureDecisionBackend { _ in throw FixtureFailure() }
    let game = CityChainGame(decisions: DecisionEngine(backend: backend), catalog: catalog("Dover"))

    do {
      _ = try await game.submit("Riverhead")
      Issue.record("Expected the backend error to propagate.")
    } catch is FixtureFailure {
      // Expected: inference errors remain errors and do not become game outcomes.
    }

    let snapshot = await game.snapshot()
    #expect(snapshot.usedCities.isEmpty)
    #expect(!snapshot.isSubmissionInProgress)
  }

  @Test("The standard reply catalog contains all 50 capitals and 50 additional cities")
  func standardCatalogHasOneHundredUniqueCities() {
    #expect(USCityCatalog.stateCapitals.count == 50)
    #expect(USCityCatalog.majorCities.count == 50)
    #expect(USCityCatalog.standard.cities.count == 100)
    #expect(Set(USCityCatalog.standard.cities.map(\.id)).count == 100)
  }

  private func catalog(_ names: String...) -> USCityCatalog {
    USCityCatalog(cities: names.map(USCity.init))
  }
}

private actor FixtureBackend: DecisionBackend {
  private let choiceIndex: Int
  private let noulAnswer: Bool
  private let abstainNoul: Bool
  private let abstainChoice: Bool
  private let failChoice: Bool
  private var prompts: [DecisionPrompt] = []

  init(
    choiceIndex: Int = 0,
    noulAnswer: Bool = true,
    abstainNoul: Bool = false,
    abstainChoice: Bool = false,
    failChoice: Bool = false
  ) {
    self.choiceIndex = choiceIndex
    self.noulAnswer = noulAnswer
    self.abstainNoul = abstainNoul
    self.abstainChoice = abstainChoice
    self.failChoice = failChoice
  }

  func predict(for prompt: DecisionPrompt) async throws -> DecisionPrediction {
    prompts.append(prompt)
    let probabilities: [Double]
    switch prompt.kind {
    case .choice where failChoice:
      throw ChoiceFailure()
    case .noul where abstainNoul:
      probabilities = [0.5, 0.5]
    case .noul:
      probabilities = noulAnswer ? [0.01, 0.99] : [0.99, 0.01]
    case .choice where abstainChoice:
      probabilities = Array(
        repeating: 1 / Double(prompt.options.count), count: prompt.options.count)
    case .choice:
      let selected = min(choiceIndex, prompt.options.count - 1)
      let otherProbability = 0.04 / Double(prompt.options.count - 1)
      probabilities = prompt.options.indices.map { $0 == selected ? 0.96 : otherProbability }
    case .score:
      probabilities = Array(
        repeating: 1 / Double(prompt.options.count), count: prompt.options.count)
    }
    return DecisionPrediction(probabilities: probabilities, modelIdentifier: "city-chain-fixture")
  }

  func receivedPrompts() -> [DecisionPrompt] { prompts }
}

private struct ChoiceFailure: Error, Sendable {}

private actor SuspendedNoulBackend: DecisionBackend {
  private var predictionContinuation: CheckedContinuation<DecisionPrediction, Never>?
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var hasStarted = false

  func predict(for prompt: DecisionPrompt) async throws -> DecisionPrediction {
    await withCheckedContinuation { continuation in
      predictionContinuation = continuation
      hasStarted = true
      let waiters = startWaiters
      startWaiters.removeAll()
      for waiter in waiters {
        waiter.resume()
      }
    }
  }

  func waitUntilStarted() async {
    guard !hasStarted else { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func release() {
    guard let predictionContinuation else { return }
    self.predictionContinuation = nil
    predictionContinuation.resume(
      returning: DecisionPrediction(
        probabilities: [0.01, 0.99],
        modelIdentifier: "city-chain-suspended-fixture"
      ))
  }
}
