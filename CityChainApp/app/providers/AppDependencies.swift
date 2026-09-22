import CityChainGame
import Foundation
import SwiftDecision

struct AppDependencies {
  private let backend: any DecisionBackend

  init(backend: any DecisionBackend = BackendNotConfigured()) {
    self.backend = backend
  }

  static func liveJev(apiKey: String? = nil) throws -> AppDependencies {
    AppDependencies(backend: try CityChainBackendFactory.makeJev(apiKey: apiKey))
  }

  func makeGame() -> CityChainGame {
    CityChainGame(decisions: DecisionEngine(backend: backend))
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
