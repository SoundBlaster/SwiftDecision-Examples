import OracleGame
import SwiftDecision
import Testing

struct OracleDistributionTraceTests {
  @Test func choiceSnapshotRetainsCallerOrderAndUnroundedScores() async throws {
    let probabilities = [0.123456789, 0.876543211]
    let backend = ClosureDecisionBackend { _ in
      DecisionPrediction(probabilities: probabilities, modelIdentifier: "export-test")
    }
    let engine = OracleGameEngine(backend: backend, fallbackEnabled: false)
    let result = try await engine.answerWithTrace(for: OracleRequest(question: "Choose a color: red or blue?"))
    let distribution = try #require(result.pipeline.first { $0.title == "Answer decision" }?.distribution)
    #expect(distribution.options == ["red", "blue"])
    #expect(distribution.probabilities == probabilities)
    #expect(distribution.confidence == probabilities[1])
  }

  @Test(arguments: [OracleMode.noul, .score])
  func orderedKindsRetainTheirOriginalLevelMeaning(mode: OracleMode) async throws {
    let backend = ClosureDecisionBackend { prompt in
      DecisionPrediction(probabilities: prompt.kind == .noul ? [0.12, 0.88] : [0.01, 0.02, 0.03, 0.94],
                         modelIdentifier: "export-test")
    }
    let result = try await OracleGameEngine(backend: backend, fallbackEnabled: false)
      .answerWithTrace(for: OracleRequest(question: "Will this work?", mode: mode))
    let distribution = try #require(result.pipeline.first { $0.title == "Answer decision" }?.distribution)
    #expect(distribution.options == (mode == .noul
      ? ["No", "Yes"] : ["Very unlikely", "Uncertain", "Likely", "Very likely"]))
    #expect(distribution.probabilities == (mode == .noul ? [0.12, 0.88] : [0.01, 0.02, 0.03, 0.94]))
  }
}
