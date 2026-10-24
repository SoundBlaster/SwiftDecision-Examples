#if canImport(FoundationModels)
import Foundation
import FoundationModels
import XCTest
import OracleGame
import SwiftDecision

@available(macOS 26.0, iOS 26.0, *)
final class AppleIntelligenceOracleBackendTests: XCTestCase {
  func testAllDecisionTypesUseTheLocalAdapterAndPreserveMetadata() async throws {
    let client = OracleGuidedFixture()
    let backend = AppleIntelligenceOracleBackend(client: client)
    XCTAssertFalse(backend.supportsTransientFailureFallback)
    XCTAssertEqual(backend.maximumResponseTime, 15)
    for (kind, count) in [(DecisionKind.noul, 2), (.choice, 3), (.score, 4)] {
      let prompt = DecisionPrompt(
        id: "oracle-fixture", kind: kind, instructions: "Pick an option", context: "Synthetic fixture",
        options: (0..<count).map { index in
          DecisionOption(
            id: kind == .noul ? (index == 0 ? "false" : "true") : String(index),
            description: "Option \(index)")
        })
      let result = try await backend.predict(for: prompt)
      XCTAssertEqual(result.probabilities.count, count)
      XCTAssertEqual(result.probabilities.reduce(0, +), 1, accuracy: 0.0001)
      XCTAssertEqual(result.modelIdentifier, backend.modelIdentifier)
    }
  }

  func testStrictOutputDoesNotSilentlyNormalize() async throws {
    let backend = AppleIntelligenceOracleBackend(client: OracleStrictFixture(), normalizeOutput: false)
    do {
      _ = try await backend.predict(for: DecisionPrompt(
        id: "strict-fixture", kind: .noul, instructions: "Is this valid?", context: "Fixture",
        options: [.init(id: "false", description: "False"), .init(id: "true", description: "True")]))
      XCTFail("A distribution summing to 0.4 must be rejected in strict mode")
    } catch DecisionError.invalidPrediction { }
  }

  func testAutomaticOraclePipelineUsesAppleMetadata() async throws {
    let backend = AppleIntelligenceOracleBackend(client: OracleGuidedFixture())
    let result = try await OracleGameEngine(backend: backend, fallbackEnabled: false)
      .answerWithTrace(for: OracleRequest(question: "Will this work?"))
    guard case let .accepted(answer) = result.outcome else {
      return XCTFail("Expected a typed local answer")
    }
    XCTAssertEqual(answer.mode, .noul)
    XCTAssertEqual(answer.source, .model(identifier: backend.modelIdentifier))
    XCTAssertNotNil(result.pipeline.first { $0.id == "Question type" })
  }

  func testAppleTimeoutDoesNotBecomeAnOfflineAnswer() async throws {
    let backend = AppleIntelligenceOracleBackend(client: OracleSlowFixture(), timeout: 0.02)
    do {
      _ = try await OracleGameEngine(backend: backend, fallbackEnabled: false)
        .answer(for: OracleRequest(question: "Will this work?", mode: .noul))
      XCTFail("Apple timeout must remain visible to the caller")
    } catch DecisionError.timedOut { }
  }

  func testLiveLocalExplicitAlternatives() async throws {
    guard ProcessInfo.processInfo.environment["ORACLE_APPLE_INTELLIGENCE_SMOKE"] == "1" else {
      throw XCTSkip("Set ORACLE_APPLE_INTELLIGENCE_SMOKE=1 for local inference")
    }
    guard case .available = AppleIntelligenceOracleBackend.availability else {
      throw XCTSkip("Apple Intelligence is unavailable on this host")
    }
    let engine = OracleGameEngine(backend: AppleIntelligenceOracleBackend(), fallbackEnabled: false)
    let result = try await engine.answerWithTrace(for: OracleRequest(question: "Hello or Kitty?"))
    XCTAssertFalse(result.pipeline.contains { $0.id == "Question type" })
    XCTAssertEqual(result.pipeline.first { $0.id == "Request routing" }?.summary, "Choice")
    switch result.outcome {
    case let .accepted(answer):
      XCTAssertEqual(answer.mode, .choice)
      XCTAssertTrue(["Hello", "Kitty"].contains(answer.displayText))
      print("Oracle explicit alternatives: accepted Choice without classification")
    case .abstained:
      print("Oracle explicit alternatives: Choice policy abstained without classification")
    case .fallback:
      XCTFail("Apple pilot must not use fallback")
    }
  }

  /// Explicit local inference only. Never uses Jev credentials or sends a network request.
  func testLiveLocalOraclePilot() async throws {
    guard ProcessInfo.processInfo.environment["ORACLE_APPLE_INTELLIGENCE_SMOKE"] == "1" else {
      throw XCTSkip("Set ORACLE_APPLE_INTELLIGENCE_SMOKE=1 for local inference")
    }
    guard case .available = AppleIntelligenceOracleBackend.availability else {
      throw XCTSkip("Apple Intelligence is unavailable on this host")
    }
    let engine = OracleGameEngine(backend: AppleIntelligenceOracleBackend(), fallbackEnabled: false)
    for (mode, question) in [
      (OracleMode.noul, "Can careful practice help me improve?"),
      (.choice, "Should I choose tea or coffee?"),
      (.score, "How likely is regular practice to improve a skill?"),
      (.automatic, "Will I enjoy learning something new?")
    ] {
      let start = ContinuousClock.now
      let result = try await engine.answerWithTrace(for: OracleRequest(question: question, mode: mode))
      print("Oracle local pilot: \(mode.rawValue), elapsed \(start.duration(to: .now))")
      switch result.outcome {
      case let .accepted(answer):
        print("Oracle local pilot: \(mode.rawValue) accepted as \(answer.mode.rawValue)")
        XCTAssertEqual(answer.source, .model(identifier: "apple.foundation-models.on-device"))
        XCTAssertFalse(answer.displayText.isEmpty)
      case .abstained:
        print("Oracle local pilot: \(mode.rawValue) abstained")
        // Uncertainty is valid; an invented or offline answer would conceal a pilot failure.
        XCTAssertFalse(result.pipeline.isEmpty)
      case .fallback:
        XCTFail("Apple pilot must not silently return a fallback")
      }
    }
  }
}

@available(macOS 26.0, iOS 26.0, *)
private struct OracleGuidedFixture: FoundationModelsDecisionClient {
  func generate(_ request: FoundationModelsDecisionRequest) async throws -> GeneratedContent {
    let object = try JSONSerialization.jsonObject(with: Data(request.prompt.utf8)) as! [String: Any]
    let options = object["options"] as! [[String: Any]]
    let kind = object["kind"] as! String
    // The automatic router should choose Noul (first of its four options).
    let selected = kind == "noul" ? 1 : 0
    return GeneratedContent(properties: ["weights": options.indices.map { $0 == selected ? 1.0 : 0.0 }])
  }
}

@available(macOS 26.0, iOS 26.0, *)
private struct OracleStrictFixture: FoundationModelsDecisionClient {
  func generate(_ request: FoundationModelsDecisionRequest) async throws -> GeneratedContent {
    GeneratedContent(properties: ["probabilities": [0.2, 0.2]])
  }
}
@available(macOS 26.0, iOS 26.0, *)
private struct OracleSlowFixture: FoundationModelsDecisionClient {
  func generate(_ request: FoundationModelsDecisionRequest) async throws -> GeneratedContent {
    try await Task.sleep(for: .milliseconds(200))
    return GeneratedContent(properties: ["weights": [0.0, 1.0]])
  }
}
#endif
