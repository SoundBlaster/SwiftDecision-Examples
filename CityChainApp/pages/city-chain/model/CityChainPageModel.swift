import CityChainGame
import Foundation
import Observation
#if DEBUG
import SwiftDecision
#endif

@MainActor
@Observable
final class CityChainPageModel {
  private let game: CityChainGame
  private let autosaveStore: CityChainAutosaveStore
  private var autosaveDebounceTask: Task<Void, Never>?
  private var autosaveWriteTask: Task<Void, Never>?
  private var lastPersistedAutosave: CityChainAutosave?
  private(set) var autosaveErrorMessage: String?

  private(set) var snapshot: CityGameSnapshot?
  private(set) var latestTurnPipeline: [CityGamePipelineStage] = []
  private(set) var hasCommittedPlayerCityForCurrentTurn = false
  private(set) var isScoutThinkingStopVisible = false
  private var scoutStateMachine = ScoutStateMachine()
  var isSubmitting: Bool { scoutStateMachine.isSubmitting }
  var hasTurnFeedback: Bool { scoutStateMachine.hasTurnFeedback }
  var isScoutIdle: Bool { scoutStateMachine.isIdle }
  var scoutPresentation: ScoutPresentation { scoutStateMachine.presentation }
  private(set) var latestScoutFact: ScoutFact?
  private let factSelectionStore = ScoutFactSelectionStore()
  private var scoutThinkingStopDelayTask: Task<Void, Never>?
  var cityInput = "" {
    didSet {
      if oldValue != cityInput { scheduleAutosave(draft: cityInput) }
    }
  }
  private var regularStatusMessage = String(localized: "Pick a city from the U.S. atlas to start your trip.")
  var statusMessage: String {
    get { autosaveErrorMessage ?? regularStatusMessage }
    set { regularStatusMessage = newValue }
  }
#if DEBUG
  private let debugFixture: CityGameFixture?
  private let debugFixtureError: String?
  private(set) var isDebugThinkingCapture = false
  var shouldFocusInputAfterLoad = false
  private(set) var debugFixtureDiagnostic: String?
#endif

  init(game: CityChainGame, autosaveStore: CityChainAutosaveStore = CityChainAutosaveStore()) {
    self.game = game
    self.autosaveStore = autosaveStore
#if DEBUG
    self.debugFixture = nil
    self.debugFixtureError = nil
#endif
  }

#if DEBUG
  init(
    game: CityChainGame, debugFixture: CityGameFixture?, debugFixtureError: String?,
    autosaveStore: CityChainAutosaveStore = CityChainAutosaveStore()
  ) {
    self.game = game
    self.autosaveStore = autosaveStore
    self.debugFixture = debugFixture
    self.debugFixtureError = debugFixtureError
  }
#endif

#if DEBUG
  static func preview() -> CityChainPageModel {
    CityChainPageModel(
      game: CityChainGame(
        decisions: DecisionEngine(backend: PreviewDecisionBackend()),
        continuationPolicy: .previousAvailableLetter))
  }
#endif

  func load() async {
    guard snapshot == nil else { return }
    var suppressAutosaveRestore = false
    var autosaveWasRestored = false
    var restoredFromLocal = false
#if DEBUG
    if let debugFixtureError {
      suppressAutosaveRestore = true
      statusMessage = debugFixtureError
      debugFixtureDiagnostic = debugFixtureError
    } else if let debugFixture {
      suppressAutosaveRestore = true
      do {
        try await game.restore(from: debugFixture)
        cityInput = debugFixture.draft ?? ""
        shouldFocusInputAfterLoad = debugFixture.focusInput
        switch debugFixture.phase {
        case .ready:
          break
        case .thinking:
          scoutStateMachine.send(.submit)
          scoutStateMachine.send(.thinkingDelayElapsed)
          hasCommittedPlayerCityForCurrentTurn = true
          isScoutThinkingStopVisible = true
          isDebugThinkingCapture = true
        case .feedbackAccepted:
          scoutStateMachine.send(.submit)
          scoutStateMachine.send(.turnAccepted)
          statusMessage = debugFixture.feedbackMessage ?? "Fixture feedback: accepted."
        case .feedbackRejected:
          scoutStateMachine.send(.submit)
          scoutStateMachine.send(.turnRejected)
          statusMessage = debugFixture.feedbackMessage ?? "Fixture feedback: try another city."
        case .finished:
          scoutStateMachine.send(.submit)
          scoutStateMachine.send(.turnAccepted)
          statusMessage = debugFixture.endingMessage ?? "Fixture route finished."
        }
      } catch {
        statusMessage = "CityChain debug fixture: \(error.localizedDescription)"
        debugFixtureDiagnostic = statusMessage
      }
    }
#endif
    if !suppressAutosaveRestore {
      for candidate in await autosaveStore.loadCandidates() {
        let save = candidate.save
        do {
          try await game.restore(from: save.game)
          autosaveWasRestored = true
          restoredFromLocal =
            candidate.location == .applicationSupport && candidate.canPromoteToCloud
          lastPersistedAutosave = save
          cityInput = save.game.draft ?? ""
          statusMessage = save.game.feedbackMessage
            ?? String(localized: "Pick a city from the U.S. atlas to start your trip.")
        switch save.game.phase {
        case .ready: break
        case .feedbackAccepted:
          scoutStateMachine.send(.submit)
          scoutStateMachine.send(.turnAccepted)
        case .finished:
          // The finished route is restored, while transient feedback stays dismissed.
          break
        case .feedbackRejected:
          scoutStateMachine.send(.submit)
          scoutStateMachine.send(.turnRejected)
        case .thinking: break
        }
          break
        } catch {
          // Try the next storage location; route validation is atomic.
        }
      }
    }
    snapshot = await game.snapshot()
    if !suppressAutosaveRestore, !autosaveWasRestored {
      await flushAutosave(draft: cityInput)
    } else if !suppressAutosaveRestore, restoredFromLocal {
      await flushAutosave(draft: cityInput)
    }
  }

#if DEBUG
  func dismissDebugFixtureDiagnostic() {
    debugFixtureDiagnostic = nil
  }

  func exitDebugThinkingCapture() async {
    guard isDebugThinkingCapture else { return }
    await game.reset()
    snapshot = await game.snapshot()
    scoutStateMachine.send(.newRoundStarted)
    isDebugThinkingCapture = false
    hasCommittedPlayerCityForCurrentTurn = false
    isScoutThinkingStopVisible = false
    cityInput = ""
    statusMessage = String(localized: "Pick a city from the U.S. atlas to start your trip.")
    await flushAutosave(draft: cityInput)
  }
#endif

  func dismissTurnFeedback() {
    scoutStateMachine.send(.feedbackDismissed)
    latestScoutFact = nil
    let draft = cityInput
    Task { @MainActor [weak self] in
      await self?.flushAutosave(draft: draft)
    }
  }

  func flushPendingAutosave() async {
    await flushAutosave(draft: cityInput)
  }

  func startNewRound() async {
    guard !isSubmitting else { return }
    await game.reset()
    snapshot = await game.snapshot()
    scoutStateMachine.send(.newRoundStarted)
    cityInput = ""
    latestScoutFact = nil
    latestTurnPipeline = []
    statusMessage = String(localized: "Pick a city from the U.S. atlas to start your trip.")
    await flushAutosave(draft: cityInput)
  }

  func submit(_ cityName: String) async -> Bool {
    guard !isSubmitting else { return false }
    // If the process exits while inference is suspended, relaunch with the
    // previous completed route and the exact city the player submitted.
    await flushAutosave(draft: cityName)
    let durableSave = lastPersistedAutosave
    scoutStateMachine.send(.submit)
    hasCommittedPlayerCityForCurrentTurn = false
    isScoutThinkingStopVisible = false
    latestScoutFact = nil
    // Let quick local rule failures return immediately without flashing the
    // thinking pose. Accepted turns stay in this pose while the engine works.
    let thinkingTask = Task { @MainActor in
      do {
        try await Task.sleep(for: .milliseconds(300))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      scoutStateMachine.send(.thinkingDelayElapsed)
    }
    defer {
      thinkingTask.cancel()
      scoutThinkingStopDelayTask?.cancel()
      scoutThinkingStopDelayTask = nil
      hasCommittedPlayerCityForCurrentTurn = false
      isScoutThinkingStopVisible = false
    }

    do {
      let tracedResult = try await game.submitWithTrace(cityName) { [weak self] committedSnapshot in
        guard let self else { return }
        self.snapshot = committedSnapshot
        self.hasCommittedPlayerCityForCurrentTurn = true
        self.scoutThinkingStopDelayTask?.cancel()
        self.scoutThinkingStopDelayTask = Task { @MainActor [weak self] in
          do {
            try await Task.sleep(for: .milliseconds(450))
          } catch {
            return
          }
          guard !Task.isCancelled, let self, self.isSubmitting else { return }
          self.isScoutThinkingStopVisible = true
        }
      }
      let result = tracedResult.result
      let updatedSnapshot = await game.snapshot()
      let accepted = Self.didAcceptPlayerTurn(result)
      if accepted {
        await thinkingTask.value
      } else {
        thinkingTask.cancel()
      }
      latestTurnPipeline = tracedResult.pipeline
      statusMessage = Self.message(for: result)
      if accepted, let city = Self.factCity(for: result),
         let fact = factSelectionStore.nextFact(for: city)
      {
        latestScoutFact = fact
        statusMessage += " Did you know? \(fact.text)"
      }
      snapshot = updatedSnapshot
      scoutStateMachine.send(accepted ? .turnAccepted : .turnRejected)
      await flushAutosave(draft: cityInput)
      return accepted
    } catch {
      latestTurnPipeline.append(
        CityGamePipelineStage(
          id: "turn-error", title: "Turn error",
          summary: "The turn failed with \(String(reflecting: type(of: error)))."))
      statusMessage = String(localized: "I can't check that city right now. Try a suggested city!")
      if let durableSave {
        try? await game.restore(from: durableSave.game)
      }
      snapshot = await game.snapshot()
      scoutStateMachine.send(.turnRejected)
      await flushAutosave(draft: cityName)
      return false
    }
  }

  private static func didAcceptPlayerTurn(_ result: CityGameTurnResult) -> Bool {
    switch result {
    case .computerReplied, .playerWonNoAvailableReply, .playerWonBecauseComputerAbstained:
      true
    default:
      false
    }
  }

  private static func factCity(for result: CityGameTurnResult) -> USCity? {
    switch result {
    case .computerReplied(_, let computerCity, _):
      computerCity
    case .playerWonNoAvailableReply(let playerCity, _),
         .playerWonBecauseComputerAbstained(let playerCity, _):
      playerCity
    default:
      nil
    }
  }

  private func scheduleAutosave(draft: String) {
    autosaveDebounceTask?.cancel()
    autosaveDebounceTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(350))
      } catch {
        return
      }
      guard !Task.isCancelled, let self else { return }
      self.enqueueAutosaveWrite(draft: draft)
    }
  }

  private func flushAutosave(draft: String) async {
    autosaveDebounceTask?.cancel()
    autosaveDebounceTask = nil
    enqueueAutosaveWrite(draft: draft)
    await autosaveWriteTask?.value
  }

  private func enqueueAutosaveWrite(draft: String) {
    guard let snapshot else { return }
    let phase: CityGameFixturePhase
    if snapshot.isFinished {
      phase = .finished
    } else {
      switch scoutStateMachine.state {
      case .celebrating: phase = .feedbackAccepted
      case .tryAnother: phase = .feedbackRejected
      default: phase = .ready
      }
    }
    let ending: CityGameFixtureEnding?
    switch snapshot.ending {
    case .noAvailableReply: ending = .noAvailableReply
    case .computerAbstained: ending = .computerAbstained
    case nil: ending = nil
    }
    let route = snapshot.usedCities.enumerated().map { index, city in
      CityGameFixture.Turn(role: index.isMultiple(of: 2) ? .player : .computer, city: city.name)
    }
    let fixture = CityGameFixture(
      route: route, draft: draft, phase: phase,
      feedbackMessage: phase == .ready ? nil : statusMessage,
      ending: ending, endingMessage: phase == .finished ? statusMessage : nil,
      consecutiveMistakes: snapshot.consecutiveMistakes, cityHint: snapshot.cityHint)
    let save = CityChainAutosave(game: fixture)
    let previousWrite = autosaveWriteTask
    autosaveWriteTask = Task { [weak self] in
      await previousWrite?.value
      guard let self else { return }
      do {
        try await self.autosaveStore.write(save)
        self.lastPersistedAutosave = save
        self.autosaveErrorMessage = nil
      } catch {
        self.autosaveErrorMessage = error.localizedDescription
      }
    }
  }

  private static func message(for result: CityGameTurnResult) -> String {
    switch result {
    case .rejected(.emptyInput):
      return String(localized: "Type a city name to play.")
    case .rejected(.cityNameHasNoLatinLetters):
      return String(localized: "Use English letters in city names.")
    case .rejected(.wrongStartingLetter(let expected, _)):
      return Self.format("Find a city that starts with %@!", String(expected))
    case .rejected(.alreadyUsed(let city)):
      return Self.format("We already visited %@. Pick another!", city.name)
    case .cityNotRecognized(let city):
      return Self.format("I couldn't find %@ in my atlas yet. Try a suggested city!", city.name)
    case .cityVerificationAbstained(let city, _):
      return Self.format("I'm not sure about %@ yet. Try a suggested city!", city.name)
    case .cityVerificationFallback(let city, _):
      return Self.format("Let's try a city from the atlas instead of %@.", city.name)
    case .computerReplied(let playerCity, let computerCity, let selection):
      switch selection {
      case .onlyAvailableCity:
        return Self.format(
          "Great job with %@! My only city was %@.", playerCity.name, computerCity.name)
      case .acceptedByDecision:
        return Self.format("Great job with %@! I choose %@.", playerCity.name, computerCity.name)
      case .fallbackByDecision:
        return Self.format("Great job with %@! I choose %@.", playerCity.name, computerCity.name)
      case .randomFallback:
        return Self.format(
          "Great job with %@! I picked %@ from my atlas.", playerCity.name, computerCity.name)
      }
    case .playerWonNoAvailableReply(_, let startingLetter):
      return Self.format(
        "No more cities start with %@. You win this round!", String(startingLetter))
    case .playerWonBecauseComputerAbstained:
      return String(localized: "I can't think of a city. You win this round!")
    case .submissionInProgress:
      return String(localized: "One moment, I'm thinking!")
    case .gameAlreadyFinished:
      return String(localized: "This round is over. Start a new trip!")
    }
  }

  private static func format(_ key: String, _ arguments: CVarArg...) -> String {
    String(
      format: String(localized: String.LocalizationValue(key)),
      locale: Locale(identifier: "en_US"),
      arguments: arguments)
  }
}

#if DEBUG
private struct PreviewDecisionBackend: DecisionBackend {
  func predict(for prompt: DecisionPrompt) async throws -> DecisionPrediction {
    throw PreviewBackendUnavailable()
  }
}

private struct PreviewBackendUnavailable: Error {}
#endif
