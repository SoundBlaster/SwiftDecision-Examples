import Foundation
import SwiftDecision
import SwiftJev
import Testing

@testable import CityChainGame

@Suite("City-chain rules")
struct CityChainGameTests {
  @Test("The Jev backend factory validates configuration without making a request")
  func jevFactoryValidatesConfiguration() async throws {
    let transport = RecordingJevTransport()
    do {
      _ = try CityChainBackendFactory.makeJev(apiKey: "", transport: transport)
      Issue.record("Expected an empty API key to be rejected.")
    } catch let error as JevDecisionBackendError {
      #expect(error == .missingAPIKey)
    } catch {
      Issue.record("Expected JevDecisionBackendError.missingAPIKey, got \(error).")
    }

    _ = try CityChainBackendFactory.makeJev(apiKey: "fixture-key", transport: transport)
    #expect(await transport.requestCount == 0)
  }

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

  @Test("Previous-letter continuation skips exhausted letters before finding a reply")
  func previousAvailableLetterFindsAnEarlierLetter() async throws {
    let backend = FixtureBackend()
    let game = CityChainGame(
      decisions: DecisionEngine(backend: backend),
      catalog: catalog("Seattle"),
      continuationPolicy: .previousAvailableLetter
    )

    let result = try await game.submit("Mesa")

    #expect(
      result
        == .computerReplied(
          playerCity: USCity("Mesa"),
          computerCity: USCity("Seattle"),
          selection: .onlyAvailableCity
        ))
    let snapshot = await game.snapshot()
    let playerContinuation = try #require(snapshot.letterContinuations.first)
    #expect(playerContinuation.startingLetter == "S")
    #expect(playerContinuation.skippedLetters == ["A"])
  }

  @Test("Previous-letter continuation allows any reply when every letter is exhausted")
  func previousAvailableLetterFallsBackToAnyLetter() async throws {
    let backend = FixtureBackend()
    let game = CityChainGame(
      decisions: DecisionEngine(backend: backend),
      catalog: catalog("Dover"),
      continuationPolicy: .previousAvailableLetter
    )

    let result = try await game.submit("Mesa")

    #expect(
      result
        == .computerReplied(
          playerCity: USCity("Mesa"),
          computerCity: USCity("Dover"),
          selection: .onlyAvailableCity
        ))
    let snapshot = await game.snapshot()
    let playerContinuation = try #require(snapshot.letterContinuations.first)
    #expect(playerContinuation.startingLetter == nil)
    #expect(playerContinuation.skippedLetters == ["A", "S", "E", "M"])
  }

  @Test("The traced submission exposes the ordered specification and decision stages")
  func tracedSubmissionReportsPipelineAndChoiceDetails() async throws {
    let backend = FixtureBackend(choiceIndex: 2)
    let game = CityChainGame(
      decisions: DecisionEngine(backend: backend),
      catalog: catalog("Dover", "Detroit", "Durham", "Duluth", "Dublin", "Dayton")
    )

    let traced = try await game.submitWithTrace("Riverhead")

    #expect(
      traced.result
        == .computerReplied(
          playerCity: USCity("Riverhead"),
          computerCity: USCity("Durham"),
          selection: .acceptedByDecision(confidence: 0.96)
        ))
    #expect(
      traced.pipeline.map(\.id)
        == [
          "player-preflight", "city-validation", "catalog-validation", "player-continuation",
          "reply-candidates", "reply-plan", "computer-choice", "scout-thinking", "turn-commit",
          "computer-continuation",
        ])

    let candidatesStage = try #require(traced.pipeline.first { $0.id == "reply-candidates" })
    #expect(candidatesStage.events.contains { $0.name == "city.available-replies" })
    let choiceStage = try #require(traced.pipeline.first { $0.id == "computer-choice" })
    #expect(choiceStage.details.first { $0.id == "candidate-count" }?.value == "5")
    #expect(choiceStage.details.first { $0.id == "selected-city" }?.value == "Durham")
    #expect(choiceStage.details.first { $0.id == "confidence" }?.value == "96%")
  }

  @Test("Reset clears the route and allows another round")
  func resetRestoresInitialState() async throws {
    let backend = FixtureBackend()
    let game = CityChainGame(decisions: DecisionEngine(backend: backend), catalog: catalog("Dover"))

    let firstRound = try await game.submit("Riverhead")
    guard case .computerReplied = firstRound else {
      Issue.record("Expected a completed first turn before reset.")
      return
    }

    await game.reset()
    let resetSnapshot = await game.snapshot()
    #expect(resetSnapshot.usedCities.isEmpty)
    #expect(resetSnapshot.requiredStartingLetter == nil)
    #expect(resetSnapshot.ending == nil)
    #expect(resetSnapshot.consecutiveMistakes == 0)
    #expect(resetSnapshot.cityHint == nil)
    #expect(resetSnapshot.validationSource == nil)
    #expect(resetSnapshot.letterContinuations.isEmpty)
    #expect(!resetSnapshot.isSubmissionInProgress)
    #expect(!resetSnapshot.isFinished)

    #expect(
      try await game.submit("Riverhead")
        == .computerReplied(
          playerCity: USCity("Riverhead"),
          computerCity: USCity("Dover"),
          selection: .onlyAvailableCity
        ))
  }

  @Test("An invalid random fallback index safely selects the first candidate")
  func invalidRandomFallbackIndexUsesFirstCandidate() async throws {
    let backend = FixtureBackend(failChoice: true)
    let game = CityChainGame(
      decisions: DecisionEngine(backend: backend),
      catalog: catalog("Dover", "Detroit"),
      randomCandidateIndex: { $0.upperBound }
    )

    let result = try await game.submit("Riverhead")

    #expect(
      result
        == .computerReplied(
          playerCity: USCity("Riverhead"),
          computerCity: USCity("Dover"),
          selection: .randomFallback
        ))
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

  @Test("An unavailable Noul accepts a canonical city from the local catalog")
  func noulFailureFallsBackToCatalogCity() async throws {
    let backend = UnavailableBackend()
    let game = CityChainGame(
      decisions: DecisionEngine(backend: backend),
      catalog: catalog("St. Louis", "Seattle")
    )

    let result = try await game.submit("ST Louis")

    #expect(
      result
        == .computerReplied(
          playerCity: USCity("St. Louis"),
          computerCity: USCity("Seattle"),
          selection: .onlyAvailableCity
        ))
    let snapshot = await game.snapshot()
    #expect(snapshot.usedCities == [USCity("St. Louis"), USCity("Seattle")])
    #expect(snapshot.validationSource == .localCatalogFallback)
    #expect(await backend.receivedPrompts().map(\.kind) == [.noul])
  }

  @Test("A Noul abstention accepts a city when the local catalog can verify it")
  func noulAbstentionFallsBackToCatalogCity() async throws {
    let backend = FixtureBackend(abstainNoul: true)
    let game = CityChainGame(
      decisions: DecisionEngine(backend: backend),
      catalog: catalog("St. Louis", "Seattle")
    )

    let result = try await game.submit("ST Louis")

    #expect(
      result
        == .computerReplied(
          playerCity: USCity("St. Louis"),
          computerCity: USCity("Seattle"),
          selection: .onlyAvailableCity
        ))
    #expect(await game.snapshot().validationSource == .localCatalogFallback)
  }

  @Test("A Noul rejection is not overridden by local catalog membership")
  func noulRejectionTakesPrecedenceOverCatalogFallback() async throws {
    let backend = FixtureBackend(noulAnswer: false)
    let game = CityChainGame(
      decisions: DecisionEngine(backend: backend), catalog: catalog("St. Louis", "Seattle"))

    let result = try await game.submit("ST Louis")

    #expect(result == .cityNotRecognized(USCity("ST Louis")))
    let snapshot = await game.snapshot()
    #expect(snapshot.usedCities.isEmpty)
    #expect(snapshot.validationSource == nil)
  }

  @Test("After two mistakes the game hints an available city and clears it on a valid turn")
  func twoMistakesShowAndThenClearCityHint() async throws {
    let backend = FixtureBackend()
    let game = CityChainGame(
      decisions: DecisionEngine(backend: backend),
      catalog: catalog("Dover", "Riverside", "Richmond")
    )

    let firstTurn = try await game.submit("Bend")
    guard case .computerReplied = firstTurn else {
      Issue.record("Expected Dover to reply and set the next letter to R.")
      return
    }

    #expect(
      try await game.submit("Boston")
        == .rejected(.wrongStartingLetter(expected: "R", actual: "B")))
    let afterFirstMistake = await game.snapshot()
    #expect(afterFirstMistake.consecutiveMistakes == 1)
    #expect(afterFirstMistake.cityHint == nil)

    #expect(
      try await game.submit("Austin")
        == .rejected(.wrongStartingLetter(expected: "R", actual: "A")))
    let afterSecondMistake = await game.snapshot()
    #expect(afterSecondMistake.consecutiveMistakes == 2)
    #expect(afterSecondMistake.cityHint?.maskedName == "Ri•••••de")
    #expect(afterSecondMistake.cityHint?.startingLetter == "R")

    let validTurn = try await game.submit("Richmond")
    #expect(
      validTurn
        == .playerWonNoAvailableReply(playerCity: USCity("Richmond"), startingLetter: "D"))
    let afterValidTurn = await game.snapshot()
    #expect(afterValidTurn.consecutiveMistakes == 0)
    #expect(afterValidTurn.cityHint == nil)
    #expect(afterValidTurn.validationSource == .noul)
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

  @Test("Cancellation propagates and releases the submission gate without committing a city")
  func cancellationLeavesStateUnchanged() async throws {
    let backend = ClosureDecisionBackend { _ in throw CancellationError() }
    let game = CityChainGame(decisions: DecisionEngine(backend: backend), catalog: catalog("Dover"))

    do {
      _ = try await game.submit("Riverhead")
      Issue.record("Expected cancellation to propagate from the backend.")
    } catch is CancellationError {
      // Cancellation must remain cancellation instead of triggering local fallback.
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }

    let snapshot = await game.snapshot()
    #expect(snapshot.usedCities.isEmpty)
    #expect(!snapshot.isSubmissionInProgress)
  }

  @Test("The standard reply catalog contains all 50 capitals and 100 additional cities")
  func standardCatalogHasOneHundredFiftyUniqueCities() {
    #expect(USCityCatalog.stateCapitals.count == 50)
    #expect(USCityCatalog.majorCities.count == 50)
    #expect(USCityCatalog.standard.cities.count == 150)
    #expect(Set(USCityCatalog.standard.cities.map(\.id)).count == 150)
  }

  @Test("A fixture restores canonical route state and accepts the next move")
  func fixtureRestoresPlayableRoute() async throws {
    let json = #"{"version":1,"route":[{"role":"player","city":"Austin"},{"role":"computer","city":"Nashville"},{"role":"player","city":"El Paso"},{"role":"computer","city":"Olympia"},{"role":"player","city":"Akron"},{"role":"computer","city":"New Orleans"}],"draft":"Springfield"}"#
    let fixture = try JSONDecoder().decode(CityGameFixture.self, from: Data(json.utf8))
    let game = CityChainGame(
      decisions: DecisionEngine(backend: FixtureBackend()),
      continuationPolicy: .previousAvailableLetter)

    try await game.restore(from: fixture)

    let snapshot = await game.snapshot()
    #expect(snapshot.usedCities == [
      USCity("Austin", state: .texas, isStateCapital: true),
      USCity("Nashville", state: .tennessee, isStateCapital: true),
      USCity("El Paso", state: .texas),
      USCity("Olympia", state: .washington, isStateCapital: true),
      USCity("Akron"),
      USCity("New Orleans", state: .louisiana),
    ])
    #expect(snapshot.requiredStartingLetter == "S")
    #expect(snapshot.letterContinuations.count == 6)

    let result = try await game.submit(fixture.draft ?? "")
    guard case .computerReplied(let playerCity, _, _) = result else {
      Issue.record("Expected the restored game to accept its draft, got \(result).")
      return
    }
    #expect(playerCity == USCity("Springfield", state: .illinois, isStateCapital: true))
  }

  @Test("A versioned game fixture survives a JSON encode/decode round trip")
  func fixtureJSONRoundTrip() throws {
    let source = #"{"version":1,"phase":"feedbackRejected","route":[{"role":"player","city":"Austin"},{"role":"computer","city":"Nashville"}],"draft":"El Paso","feedbackMessage":"Try again","focusInput":true}"#
    let fixture = try JSONDecoder().decode(CityGameFixture.self, from: Data(source.utf8))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let encoded = try encoder.encode(fixture)
    let decoded = try JSONDecoder().decode(CityGameFixture.self, from: encoded)
    #expect(decoded == fixture)
  }

  @Test("Autosave uses one atomic file and ignores corrupt or unsupported saves")
  func autosaveStoreRecovery() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("autosave.json")
    let store = CityChainAutosaveStore(
      cloudDocumentsURL: { nil }, localFileURL: { fileURL })
    let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let fixture = CityGameFixture(
      route: [.init(role: .player, city: "Austin"), .init(role: .computer, city: "Nashville")],
      draft: "El Paso", phase: .feedbackAccepted, feedbackMessage: "Great turn!",
      consecutiveMistakes: 2, cityHint: CityHint(maskedName: "E• P•••", startingLetter: "E"))

    _ = try await store.write(CityChainAutosave(game: fixture, savedAt: savedAt))
    #expect(FileManager.default.fileExists(atPath: fileURL.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["autosave.json"])
    let restoredSave = try #require(await store.loadCandidates().first?.save)
    #expect(restoredSave.game == fixture)
    let relaunchedGame = CityChainGame(
      decisions: DecisionEngine(backend: FixtureBackend()),
      continuationPolicy: .previousAvailableLetter)
    try await relaunchedGame.restore(from: restoredSave.game)
    #expect(await relaunchedGame.snapshot().usedCities == [
      USCity("Austin", state: .texas, isStateCapital: true),
      USCity("Nashville", state: .tennessee, isStateCapital: true),
    ])
    #expect(await relaunchedGame.snapshot().consecutiveMistakes == 2)
    #expect(await relaunchedGame.snapshot().cityHint == CityHint(maskedName: "E• P•••", startingLetter: "E"))

    try Data("{broken".utf8).write(to: fileURL)
    #expect(await store.loadCandidates().isEmpty)

    let unsupported = CityChainAutosave(game: fixture, savedAt: savedAt)
    let encoded = try JSONEncoder().encode(unsupported)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object["version"] = 999
    try JSONSerialization.data(withJSONObject: object).write(to: fileURL)
    #expect(await store.loadCandidates().isEmpty)

    var legacyObject = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    legacyObject["version"] = 1
    legacyObject.removeValue(forKey: "savedAt")
    try JSONSerialization.data(withJSONObject: legacyObject).write(to: fileURL)
    let migrated = try #require(await store.loadCandidates().first?.save)
    #expect(migrated.version == CityChainAutosave.currentVersion)
    #expect(migrated.savedAt == .distantPast)
  }

  @Test("Autosave reads and writes iCloud first, with coordinated access and local fallback")
  func autosaveCloudPriorityAndFallback() async throws {
    let cloudDocuments = URL(fileURLWithPath: "/virtual/ubiquity/Documents", isDirectory: true)
    let cloudFile = cloudDocuments.appendingPathComponent("CityChain", isDirectory: true)
      .appendingPathComponent("autosave-v1.json")
    let localFile = URL(fileURLWithPath: "/virtual/support/CityChain/autosave-v1.json")
    let access = MemoryCityChainAutosaveFileAccess()
    let store = CityChainAutosaveStore(
      cloudDocumentsURL: { cloudDocuments }, localFileURL: { localFile }, fileAccess: access)
    let tieTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let cloudSave = CityChainAutosave(
      game: CityGameFixture(route: [], draft: "Austin"), savedAt: tieTimestamp)
    let localSave = CityChainAutosave(
      game: CityGameFixture(route: [], draft: "Boston"), savedAt: tieTimestamp)

    #expect(try await store.write(cloudSave) == .iCloudDocuments)
    access.setData(try JSONEncoder().encode(localSave), at: localFile)
    let candidates = await store.loadCandidates()
    #expect(candidates.map(\.location) == [.iCloudDocuments, .applicationSupport])
    #expect(candidates.map(\.save.game.draft) == ["Austin", "Boston"])
    #expect(access.coordinatedWrites == [cloudFile])
    #expect(access.coordinatedReads.contains(cloudFile))

    access.setData(Data("corrupt cloud data".utf8), at: cloudFile)
    let fallback = await store.loadCandidates()
    #expect(fallback.map(\.location) == [.applicationSupport])
    #expect(fallback.first?.save == localSave)
  }

  @Test("A newer local save outranks an older cloud save and can be promoted")
  func newestAutosaveWinsAcrossLocations() async throws {
    let cloudDocuments = URL(fileURLWithPath: "/virtual/ubiquity/Documents", isDirectory: true)
    let cloudFile = cloudDocuments.appendingPathComponent("CityChain", isDirectory: true)
      .appendingPathComponent("autosave-v1.json")
    let localFile = URL(fileURLWithPath: "/virtual/support/CityChain/autosave-v1.json")
    let access = MemoryCityChainAutosaveFileAccess()
    let oldCloudSave = CityChainAutosave(
      game: CityGameFixture(route: [], draft: "Old cloud"),
      savedAt: Date(timeIntervalSince1970: 1_700_000_000))
    let newLocalSave = CityChainAutosave(
      game: CityGameFixture(route: [
        .init(role: .player, city: "Austin"), .init(role: .computer, city: "Nashville"),
      ], draft: "El Paso"),
      savedAt: Date(timeIntervalSince1970: 1_700_000_100))
    access.setData(try JSONEncoder().encode(oldCloudSave), at: cloudFile)
    access.setData(try JSONEncoder().encode(newLocalSave), at: localFile)
    let store = CityChainAutosaveStore(
      cloudDocumentsURL: { cloudDocuments }, localFileURL: { localFile }, fileAccess: access)

    let candidates = await store.loadCandidates()
    #expect(candidates.map(\.location) == [.applicationSupport, .iCloudDocuments])
    let selected = try #require(candidates.first)
    let game = CityChainGame(
      decisions: DecisionEngine(backend: FixtureBackend()),
      continuationPolicy: .previousAvailableLetter)
    try await game.restore(from: selected.save.game)
    #expect(selected.save == newLocalSave)
    #expect(await game.snapshot().usedCities == [
      USCity("Austin", state: .texas, isStateCapital: true),
      USCity("Nashville", state: .tennessee, isStateCapital: true),
    ])

    #expect(try await store.write(selected.save) == .iCloudDocuments)
    let promotedCandidates = await store.loadCandidates()
    #expect(promotedCandidates.first?.location == .iCloudDocuments)
    #expect(promotedCandidates.first?.save == newLocalSave)
  }

  @Test("A pending cloud download uses local save without promoting over the placeholder")
  func autosaveDoesNotOverwritePendingCloudItem() async throws {
    let cloudDocuments = URL(fileURLWithPath: "/virtual/ubiquity/Documents", isDirectory: true)
    let cloudFile = cloudDocuments.appendingPathComponent("CityChain", isDirectory: true)
      .appendingPathComponent("autosave-v1.json")
    let localFile = URL(fileURLWithPath: "/virtual/support/CityChain/autosave-v1.json")
    let access = MemoryCityChainAutosaveFileAccess()
    let localSave = CityChainAutosave(game: CityGameFixture(route: [], draft: "Local copy"))
    access.setCloudReadiness(.downloadPending, at: cloudFile)
    access.setData(try JSONEncoder().encode(localSave), at: localFile)
    let store = CityChainAutosaveStore(
      cloudDocumentsURL: { cloudDocuments }, localFileURL: { localFile }, fileAccess: access)

    let candidates = await store.loadCandidates()
    #expect(candidates.map(\.location) == [.applicationSupport])
    #expect(candidates.first?.canPromoteToCloud == false)
    #expect(access.downloadRequests == [cloudFile])
    #expect(access.coordinatedReads.isEmpty)

    let nextSave = CityChainAutosave(game: CityGameFixture(route: [], draft: "New draft"))
    #expect(try await store.write(nextSave) == .applicationSupport)
    #expect(access.coordinatedWrites.isEmpty)
    #expect(access.data(at: cloudFile) == nil)
    let persisted = try JSONDecoder().decode(
      CityChainAutosave.self, from: #require(access.data(at: localFile)))
    #expect(persisted == nextSave)
  }

  @Test("An invalid cloud route falls through to a valid local autosave")
  func invalidCloudRouteFallsBackToLocal() async throws {
    let cloudDocuments = URL(fileURLWithPath: "/virtual/ubiquity/Documents", isDirectory: true)
    let cloudFile = cloudDocuments.appendingPathComponent("CityChain", isDirectory: true)
      .appendingPathComponent("autosave-v1.json")
    let localFile = URL(fileURLWithPath: "/virtual/support/CityChain/autosave-v1.json")
    let access = MemoryCityChainAutosaveFileAccess()
    let invalidCloudSave = CityChainAutosave(game: CityGameFixture(route: [
      .init(role: .player, city: "Austin"), .init(role: .computer, city: "Dallas"),
    ]))
    let validLocalSave = CityChainAutosave(game: CityGameFixture(route: [
      .init(role: .player, city: "Austin"), .init(role: .computer, city: "Nashville"),
    ], draft: "El Paso"))
    access.setData(try JSONEncoder().encode(invalidCloudSave), at: cloudFile)
    access.setData(try JSONEncoder().encode(validLocalSave), at: localFile)
    let store = CityChainAutosaveStore(
      cloudDocumentsURL: { cloudDocuments }, localFileURL: { localFile }, fileAccess: access)
    let candidates = await store.loadCandidates()
    let game = CityChainGame(
      decisions: DecisionEngine(backend: FixtureBackend()),
      continuationPolicy: .previousAvailableLetter)
    var restored: CityChainAutosaveCandidate?

    for candidate in candidates {
      do {
        try await game.restore(from: candidate.save.game)
        restored = candidate
        break
      } catch {
        continue
      }
    }

    #expect(restored?.location == .applicationSupport)
    #expect(restored?.save == validLocalSave)
    #expect(await game.snapshot().usedCities == [
      USCity("Austin", state: .texas, isStateCapital: true),
      USCity("Nashville", state: .tennessee, isStateCapital: true),
    ])
  }

  @Test("Autosave falls back after iCloud write failure and reports failure if local also fails")
  func autosaveWriteFallbackAndFailure() async throws {
    let cloudDocuments = URL(fileURLWithPath: "/virtual/ubiquity/Documents", isDirectory: true)
    let cloudFile = cloudDocuments.appendingPathComponent("CityChain", isDirectory: true)
      .appendingPathComponent("autosave-v1.json")
    let localFile = URL(fileURLWithPath: "/virtual/support/CityChain/autosave-v1.json")
    let access = MemoryCityChainAutosaveFileAccess()
    let store = CityChainAutosaveStore(
      cloudDocumentsURL: { cloudDocuments }, localFileURL: { localFile }, fileAccess: access)
    let save = CityChainAutosave(game: CityGameFixture(route: []))

    access.failWrite(at: cloudFile)
    #expect(try await store.write(save) == .applicationSupport)
    #expect(access.data(at: localFile) != nil)
    #expect(access.coordinatedWrites == [cloudFile])
    #expect(access.uncoordinatedWrites == [localFile])

    access.failWrite(at: localFile)
    do {
      _ = try await store.write(save)
      Issue.record("Expected persistence to fail when both locations reject writes.")
    } catch let error as CityChainAutosaveError {
      guard case .bothLocationsUnavailable = error else {
        Issue.record("Unexpected autosave error: \(error)")
        return
      }
    }
  }

  @Test("An invalid autosave route can be replaced after an atomic restore failure")
  func invalidAutosaveCanBeReplaced() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("autosave.json")
    let store = CityChainAutosaveStore(cloudDocumentsURL: { nil }, localFileURL: { fileURL })
    let invalid = CityGameFixture(
      route: [.init(role: .player, city: "Austin"), .init(role: .computer, city: "Dallas")])
    _ = try await store.write(CityChainAutosave(game: invalid))
    let loaded = try #require(await store.loadCandidates().first?.save)
    let game = CityChainGame(
      decisions: DecisionEngine(backend: FixtureBackend()),
      continuationPolicy: .previousAvailableLetter)

    do {
      try await game.restore(from: loaded.game)
      Issue.record("Expected the broken route to be rejected.")
    } catch let error as CityGameFixtureError {
      #expect(error == .brokenChain(city: "Dallas", expected: "N"))
    }
    #expect(await game.snapshot().usedCities.isEmpty)

    let fresh = CityGameFixture(route: [])
    _ = try await store.write(CityChainAutosave(game: fresh))
    #expect(await store.loadCandidates().first?.save.game == fresh)
  }

  @Test("Fixture restoration rejects malformed turns, duplicates, and broken chains")
  func fixtureRejectsInvalidRoute() async throws {
    let cases: [(String, CityGameFixtureError)] = [
      (#"{"version":2,"route":[]}"#, .unsupportedVersion(2)),
      (#"{"version":2,"route":[{"role":"player","city":"Austin"}]}"#,
       .unsupportedVersion(2)),
      (#"{"version":1,"route":[{"role":"player","city":"Austin"}]}"#,
       .invalidRouteLength(phase: "ready")),
      (#"{"version":1,"route":[{"role":"player","city":"Austin"},{"role":"player","city":"Nashville"}]}"#,
       .invalidTurnRole(index: 1, expected: "computer")),
      (#"{"version":1,"route":[{"role":"player","city":"Austin"},{"role":"computer","city":"Dallas"}]}"#,
       .brokenChain(city: "Dallas", expected: "N")),
      (#"{"version":1,"route":[{"role":"player","city":"Austin"},{"role":"computer","city":"Nashville"},{"role":"player","city":"Austin"},{"role":"computer","city":"El Paso"}]}"#,
       .duplicateCity("Austin")),
    ]
    for (json, expectedError) in cases {
      let fixture = try JSONDecoder().decode(CityGameFixture.self, from: Data(json.utf8))
      let game = CityChainGame(
        decisions: DecisionEngine(backend: FixtureBackend()),
        continuationPolicy: .previousAvailableLetter)
      do {
        try await game.restore(from: fixture)
        Issue.record("Expected fixture error \(expectedError).")
      } catch let error as CityGameFixtureError {
        #expect(error == expectedError)
      }
      #expect(await game.snapshot().usedCities.isEmpty)
    }
  }

  @Test("Fixtures represent ready, thinking, feedback, and finished screen phases")
  func fixturePhasesRestoreConsistentEngineSnapshots() async throws {
    let baseRoute = #"[{"role":"player","city":"Austin"},{"role":"computer","city":"Nashville"}]"#
    let fixtures = [
      #"{"version":1,"phase":"ready","route":[{"role":"player","city":"Riverhead"},{"role":"computer","city":"Durham"}]}"#,
      #"{"version":1,"phase":"thinking","route":[{"role":"player","city":"Austin"},{"role":"computer","city":"Nashville"},{"role":"player","city":"El Paso"}]}"#,
      "{\"version\":1,\"phase\":\"feedbackAccepted\",\"feedbackMessage\":\"Accepted!\",\"route\":\(baseRoute)}",
      "{\"version\":1,\"phase\":\"feedbackRejected\",\"feedbackMessage\":\"Try another city.\",\"route\":\(baseRoute)}",
      #"{"version":1,"phase":"finished","ending":"computerAbstained","endingMessage":"Scout passed.","route":[{"role":"player","city":"Austin"}]}"#,
    ]
    for json in fixtures {
      let fixture = try JSONDecoder().decode(CityGameFixture.self, from: Data(json.utf8))
      let game = CityChainGame(
        decisions: DecisionEngine(backend: FixtureBackend()),
        continuationPolicy: .previousAvailableLetter)
      try await game.restore(from: fixture)
      let snapshot = await game.snapshot()
      #expect(snapshot.usedCities.count == fixture.route.count)
      #expect(snapshot.isFinished == (fixture.phase == .finished))
      if fixture.phase == .thinking {
        #expect(fixture.route.count.isMultiple(of: 2) == false)
      }
    }
  }

  @Test("An invalid restore leaves an existing game route unchanged")
  func fixtureRestoreIsAtomic() async throws {
    let valid = try JSONDecoder().decode(
      CityGameFixture.self,
      from: Data(#"{"version":1,"route":[{"role":"player","city":"Austin"},{"role":"computer","city":"Nashville"}]}"#.utf8))
    let invalid = try JSONDecoder().decode(
      CityGameFixture.self,
      from: Data(#"{"version":1,"phase":"finished","ending":"noAvailableReply","route":[{"role":"player","city":"Austin"}]}"#.utf8))
    let game = CityChainGame(
      decisions: DecisionEngine(backend: FixtureBackend()),
      continuationPolicy: .previousAvailableLetter)
    try await game.restore(from: valid)
    let before = await game.snapshot()
    do {
      try await game.restore(from: invalid)
      Issue.record("Expected the invalid route to be rejected.")
    } catch let error as CityGameFixtureError {
      #expect(error == .endingDoesNotMatchPhase)
    }
    #expect(await game.snapshot() == before)
  }

  private func catalog(_ names: String...) -> USCityCatalog {
    USCityCatalog(cities: names.map { USCity($0) })
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

private struct BackendUnavailable: Error, Sendable {}

private actor UnavailableBackend: DecisionBackend {
  private var prompts: [DecisionPrompt] = []

  func predict(for prompt: DecisionPrompt) async throws -> DecisionPrediction {
    prompts.append(prompt)
    throw BackendUnavailable()
  }

  func receivedPrompts() -> [DecisionPrompt] { prompts }
}

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

private actor RecordingJevTransport: JevHTTPTransport {
  private(set) var requestCount = 0

  func send(_ request: JevHTTPRequest) async throws -> JevHTTPResponse {
    requestCount += 1
    return JevHTTPResponse(statusCode: 500, body: Data())
  }
}

private final class MemoryCityChainAutosaveFileAccess: CityChainAutosaveFileAccess, @unchecked Sendable {
  private let lock = NSLock()
  private var files: [URL: Data] = [:]
  private var writeFailures = Set<URL>()
  private var readFailures = Set<URL>()
  private var coordinatedReadURLs: [URL] = []
  private var coordinatedWriteURLs: [URL] = []
  private var uncoordinatedWriteURLs: [URL] = []
  private var cloudReadinessByURL: [URL: CityChainCloudReadiness] = [:]
  private var downloadRequestURLs: [URL] = []

  var coordinatedReads: [URL] { lock.withLock { coordinatedReadURLs } }
  var coordinatedWrites: [URL] { lock.withLock { coordinatedWriteURLs } }
  var uncoordinatedWrites: [URL] { lock.withLock { uncoordinatedWriteURLs } }
  var downloadRequests: [URL] { lock.withLock { downloadRequestURLs } }

  func setData(_ data: Data, at url: URL) {
    lock.withLock { files[url] = data }
  }

  func data(at url: URL) -> Data? {
    lock.withLock { files[url] }
  }

  func failWrite(at url: URL) {
    _ = lock.withLock { writeFailures.insert(url) }
  }

  func setCloudReadiness(_ readiness: CityChainCloudReadiness, at url: URL) {
    lock.withLock { cloudReadinessByURL[url] = readiness }
  }

  func cloudReadiness(at url: URL) -> CityChainCloudReadiness {
    lock.withLock {
      let readiness = cloudReadinessByURL[url] ?? .ready
      if readiness == .downloadPending { downloadRequestURLs.append(url) }
      return readiness
    }
  }

  func createDirectory(at url: URL) throws {}

  func read(from url: URL, coordinate: Bool) throws -> Data {
    try lock.withLock {
      if coordinate { coordinatedReadURLs.append(url) }
      guard !readFailures.contains(url) else { throw CocoaError(.fileReadNoPermission) }
      guard let data = files[url] else { throw CocoaError(.fileNoSuchFile) }
      return data
    }
  }

  func write(_ data: Data, to url: URL, coordinate: Bool) throws {
    try lock.withLock {
      if coordinate { coordinatedWriteURLs.append(url) }
      else { uncoordinatedWriteURLs.append(url) }
      guard !writeFailures.contains(url) else { throw CocoaError(.fileWriteNoPermission) }
      files[url] = data
    }
  }
}
