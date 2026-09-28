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
    CityChainGame(
      decisions: DecisionEngine(backend: backend),
      continuationPolicy: .previousAvailableLetter)
  }

  @MainActor
  func makePageModel() -> CityChainPageModel {
    CityChainPageModel(game: makeGame())
  }

#if DEBUG
  @MainActor
  func makePageModel(debugFixture: CityGameFixture?, fixtureError: String?) -> CityChainPageModel {
    CityChainPageModel(game: makeGame(), debugFixture: debugFixture, debugFixtureError: fixtureError)
  }

  static func debugFixtureFromLaunchArguments(_ arguments: [String]) -> (CityGameFixture?, String?) {
    let inlineKey = "-citychain-fixture-json"
    let fileKey = "-citychain-fixture-file"
    let decoder = JSONDecoder()
    do {
      if let index = arguments.firstIndex(of: inlineKey) {
        guard arguments.indices.contains(index + 1) else {
          return (nil, "CityChain debug fixture: missing JSON value after \(inlineKey).")
        }
        return (try decoder.decode(CityGameFixture.self, from: Data(arguments[index + 1].utf8)), nil)
      }
      if let index = arguments.firstIndex(of: fileKey) {
        guard arguments.indices.contains(index + 1) else {
          return (nil, "CityChain debug fixture: missing path after \(fileKey).")
        }
        let url = URL(fileURLWithPath: arguments[index + 1])
        return (try decoder.decode(CityGameFixture.self, from: Data(contentsOf: url)), nil)
      }
      return (nil, nil)
    } catch {
      return (nil, "CityChain debug fixture: \(error.localizedDescription)")
    }
  }
#endif
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
