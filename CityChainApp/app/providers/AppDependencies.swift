import CityChainGame
import Foundation
import SwiftDecision

struct AppDependencies {
  func makeGame() -> CityChainGame {
    CityChainGame(decisions: DecisionEngine(backend: BackendNotConfigured()))
  }

  @MainActor
  func makePageModel() -> CityChainPageModel {
    CityChainPageModel(game: makeGame())
  }
}

private struct BackendNotConfigured: DecisionBackend {
  func predict(for prompt: DecisionPrompt) async throws -> DecisionPrediction {
    throw BackendNotConfiguredError()
  }
}

private struct BackendNotConfiguredError: Error, LocalizedError, Sendable {
  var errorDescription: String? {
    "No model backend is configured yet. The game engine is ready for an injected DecisionBackend."
  }
}
