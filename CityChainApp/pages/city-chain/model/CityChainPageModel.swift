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

  private(set) var snapshot: CityGameSnapshot?
  private(set) var latestTurnPipeline: [CityGamePipelineStage] = []
  private(set) var isSubmitting = false
  private(set) var hasTurnFeedback = false
  private(set) var scoutPresentation = ScoutPresentation()
  var cityInput = ""
  var statusMessage = String(localized: "Pick a city from the U.S. atlas to start your trip.")

  init(game: CityChainGame) {
    self.game = game
  }

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
    snapshot = await game.snapshot()
    scoutPresentation.present(.welcome)
  }

  func dismissTurnFeedback() {
    hasTurnFeedback = false
  }

  func startNewRound() async {
    guard !isSubmitting else { return }
    await game.reset()
    cityInput = ""
    hasTurnFeedback = false
    latestTurnPipeline = []
    statusMessage = String(localized: "Pick a city from the U.S. atlas to start your trip.")
    snapshot = await game.snapshot()
    scoutPresentation.present(.welcome)
  }

  func submit(_ cityName: String) async -> Bool {
    guard !isSubmitting else { return false }
    isSubmitting = true
    hasTurnFeedback = true
    // Let quick local rule failures return immediately without flashing the
    // thinking pose. Accepted turns stay in this pose while the engine works.
    let thinkingTask = Task { @MainActor in
      do {
        try await Task.sleep(for: .milliseconds(300))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      scoutPresentation.present(.thinking)
    }
    defer {
      thinkingTask.cancel()
      isSubmitting = false
    }

    do {
      let tracedResult = try await game.submitWithTrace(cityName) { [weak self] committedSnapshot in
        self?.snapshot = committedSnapshot
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
      snapshot = updatedSnapshot
      scoutPresentation.present(accepted ? .celebration : .tryAnother)
      return accepted
    } catch {
      latestTurnPipeline.append(
        CityGamePipelineStage(
          id: "turn-error", title: "Turn error",
          summary: "The turn failed with \(String(reflecting: type(of: error)))."))
      statusMessage = String(localized: "I can't check that city right now. Try a suggested city!")
      snapshot = await game.snapshot()
      scoutPresentation.present(.tryAnother)
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
