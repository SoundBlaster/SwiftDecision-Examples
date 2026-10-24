#if canImport(FoundationModels)
import Foundation
import FoundationModels
import XCTest
import OracleGame
import SwiftDecision

/// Opt-in diagnostic: output contract and index mapping, not a statistical quality benchmark.
@available(macOS 26.0, iOS 26.0, *)
final class OracleChoiceOrderDiagnosticTests: XCTestCase {
  func testLiveStrictChoiceDiagnostic() async throws {
    try requireLocalDiagnostic()
    let recorder = ChoiceDiagnosticRecorder()
    let backend = AppleIntelligenceOracleBackend(
      client: ChoiceDiagnosticClient(recorder: recorder, outputProperty: "probabilities"),
      normalizeOutput: false, timeout: 5)
    let engine = DecisionEngine(backend: backend, configuration: .init(timeout: 5))
    for sample in semanticSamples {
      await recorder.reset()
      do {
        let result = try await engine.choice(
          instructions: sample.question, context: sample.question,
          options: sample.options.map { ChoiceOption(label: $0, description: $0) })
        let values = await recorder.values()
        let data = try JSONSerialization.data(withJSONObject: [
          "question": sample.question, "raw_probabilities": values.raw,
          "probabilities": result.probabilities, "selected": result.value ?? "abstained"
        ], options: [.sortedKeys])
        print("ORACLE_STRICT_DIAGNOSTIC " + String(decoding: data, as: UTF8.self))
      } catch {
        let values = await recorder.values()
        print("ORACLE_STRICT_DIAGNOSTIC invalid output: \(sample.question), raw=\(values.raw), errorType=\(type(of: error))")
      }
    }
  }

  /// Control experiment: a categorical schema, not the probability-vector adapter contract.
  func testLiveSingleIDChoiceDiagnostic() async throws {
    try requireLocalDiagnostic()
    let schema = try GenerationSchema(root: DynamicGenerationSchema(
      name: "ChoiceSelection", properties: [
        .init(name: "selectedOptionID", description: "ID of the best-fitting option",
          schema: DynamicGenerationSchema(type: String.self, guides: [.anyOf(["0", "1"])]))
      ]), dependencies: [])
    for sample in semanticSamples {
      let session = LanguageModelSession(model: .default, instructions: """
        Choose the option that satisfies the user's instruction. Return its selectedOptionID:
        0 for the first option or 1 for the second option. Return only the requested structure.
        """)
      let response = try await session.respond(to: """
        Instruction: \(sample.question)
        Options:
        0: \(sample.options[0])
        1: \(sample.options[1])
        """, schema: schema, options: GenerationOptions(samplingMode: .greedy))
      let id = try response.content.value(String.self, forProperty: "selectedOptionID")
      let index = try XCTUnwrap(Int(id))
      XCTAssertTrue(sample.options.indices.contains(index))
      guard sample.options.indices.contains(index) else { continue }
      print("ORACLE_ID_DIAGNOSTIC \(sample.question), id=\(id), selected=\(sample.options[index])")
    }
  }

  private var semanticSamples: [(question: String, options: [String])] {
    [
      ("Choose the star: Hello or Sun", ["Hello", "Sun"]),
      ("Choose the star: Sun or Hello", ["Sun", "Hello"]),
      ("Choose a farewell: Hello or Goodbye", ["Hello", "Goodbye"]),
      ("Choose a farewell: Goodbye or Hello", ["Goodbye", "Hello"])
    ]
  }

  private func requireLocalDiagnostic() throws {
    guard ProcessInfo.processInfo.environment["ORACLE_APPLE_CHOICE_DIAGNOSTIC"] == "1" else {
      throw XCTSkip("Set ORACLE_APPLE_CHOICE_DIAGNOSTIC=1 for local order diagnostics")
    }
    guard case .available = AppleIntelligenceOracleBackend.availability else {
      throw XCTSkip("Apple Intelligence unavailable")
    }
  }

  func testLiveChoiceOrderDiagnostic() async throws {
    guard ProcessInfo.processInfo.environment["ORACLE_APPLE_CHOICE_DIAGNOSTIC"] == "1" else {
      throw XCTSkip("Set ORACLE_APPLE_CHOICE_DIAGNOSTIC=1 for local order diagnostics")
    }
    guard case .available = AppleIntelligenceOracleBackend.availability else {
      throw XCTSkip("Apple Intelligence unavailable")
    }
    let samples = [
      "hello or kitty", "kitty or hello",
      "Hello or Goodbye", "Goodbye or Hello",
      "Hello or Hi", "Hi or Hello",
      "Hello or Sun", "Sun or Hello",
      "Choose the star: Hello or Sun", "Choose the star: Sun or Hello",
      "Choose a farewell: Hello or Goodbye", "Choose a farewell: Goodbye or Hello"
    ]
    let recorder = ChoiceDiagnosticRecorder()
    let apple = AppleIntelligenceOracleBackend(
      client: ChoiceDiagnosticClient(recorder: recorder), timeout: 5)
    let engine = OracleGameEngine(
      backend: ChoiceDiagnosticBackend(apple: apple, recorder: recorder), fallbackEnabled: false)
    let started = ContinuousClock.now
    for question in samples {
      guard started.duration(to: .now) < .seconds(30) else {
        return XCTFail("Diagnostic budget exhausted")
      }
      await recorder.reset()
      let result = try await engine.answerWithTrace(for: OracleRequest(question: question))
      let values = await recorder.values()
      var row: [String: Any] = [
        "question": question, "raw_weights": values.raw, "probabilities": values.normalized
      ]
      switch result.outcome {
      case let .accepted(answer):
        XCTAssertEqual(answer.mode, .choice)
        row["outcome"] = "accepted"
        row["selected"] = answer.displayText
      case .abstained:
        row["outcome"] = "abstained"
      case .fallback:
        XCTFail("Local diagnostic must not use fallback")
        row["outcome"] = "fallback"
      }
      XCTAssertFalse(result.pipeline.contains { $0.id == "Question type" })
      let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
      print("ORACLE_CHOICE_DIAGNOSTIC " + String(decoding: data, as: UTF8.self))
    }
  }
}

@available(macOS 26.0, iOS 26.0, *)
private struct ChoiceDiagnosticClient: FoundationModelsDecisionClient {
  let recorder: ChoiceDiagnosticRecorder
  var outputProperty: String = "weights"
  func generate(_ request: FoundationModelsDecisionRequest) async throws -> GeneratedContent {
    let session = LanguageModelSession(model: .default, instructions: request.instructions)
    let response = try await session.respond(
      to: request.prompt, schema: request.schema, options: GenerationOptions(samplingMode: .greedy))
    let raw = try response.content.value([Double].self, forProperty: outputProperty)
    await recorder.record(raw: raw)
    return response.content
  }
}

@available(macOS 26.0, iOS 26.0, *)
private struct ChoiceDiagnosticBackend: OracleBackendMetadata {
  let apple: AppleIntelligenceOracleBackend
  let recorder: ChoiceDiagnosticRecorder
  var modelIdentifier: String { apple.modelIdentifier }
  var maximumResponseTime: TimeInterval? { apple.maximumResponseTime }
  func predict(for prompt: DecisionPrompt) async throws -> DecisionPrediction {
    let result = try await apple.predict(for: prompt)
    await recorder.record(normalized: result.probabilities)
    return result
  }
}

private actor ChoiceDiagnosticRecorder {
  private var raw: [Double] = []
  private var normalized: [Double] = []
  func reset() { raw = []; normalized = [] }
  func record(raw: [Double]) { self.raw = raw }
  func record(normalized: [Double]) { self.normalized = normalized }
  func values() -> (raw: [Double], normalized: [Double]) { (raw, normalized) }
}
#endif
