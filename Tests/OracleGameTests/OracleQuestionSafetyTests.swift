import Foundation
import Testing
import SwiftDecision
@testable import OracleGame

@Suite("Oracle question safety")
struct OracleQuestionSafetyTests {
  @Test(arguments: [
    ("Should I kill myself?", OracleSafetyCategory.selfHarm),
    ("I want to die", .selfHarm),
    ("Стоит ли мне покончить с собой?", .selfHarm),
    ("Думаю о самоубийстве", .selfHarm),
    ("Should I kill someone?", .harmToPeople),
    ("Should I kill Alex?", .harmToPeople),
    ("Will he hurt me?", .harmToPeople),
    ("Стоит ли убить человека?", .harmToPeople),
    ("Стоит ли убить соседа?", .harmToPeople),
    ("Может ли он навредить ей?", .harmToPeople),
  ])
  func explicitRiskIsRecognized(question: String, category: OracleSafetyCategory) {
    #expect(OracleQuestionSafetySpec().decide(question) == category)
  }

  @Test(arguments: ["Tea or coffee?", "Will I get the job?", "How can I kill time?", "Будет ли завтра дождь?"])
  func ordinaryQuestionsRemainAvailable(question: String) {
    #expect(OracleQuestionSafetySpec().decide(question) == nil)
  }

  @Test(arguments: OracleMode.allCases)
  func safetyStopsEveryModeBeforeCallingBackend(mode: OracleMode) async throws {
    let calls = SafetyBackendCalls()
    let backend = ClosureDecisionBackend { prompt in
      await calls.increment()
      return DecisionPrediction(probabilities: Array(repeating: 0.5, count: prompt.options.count),
                                modelIdentifier: "unexpected-call")
    }
    let result = try await OracleGameEngine(backend: backend).answerWithTrace(
      for: OracleRequest(question: "Should I kill myself?", mode: mode))
    #expect(result.outcome == .safetyIntervention(.selfHarm))
    #expect(await calls.count == 0)
    #expect(result.pipeline.isEmpty)
  }

  @Test func safetyAlsoPrecedesRandomFallback() async throws {
    let result = try await OracleGameEngine().randomAnswerWithTrace(
      for: OracleRequest(question: "Should I kill someone?"))
    #expect(result.outcome == .safetyIntervention(.harmToPeople))
    #expect(result.pipeline.isEmpty)
  }

  @Test func safetyPrecedesOpenCircuitFallback() async throws {
    let calls = SafetyBackendCalls()
    let engine = OracleGameEngine(backend: SafetyFailingBackend(calls: calls))
    _ = try await engine.answer(for: OracleRequest(question: "Will it rain?", mode: .noul))
    let result = try await engine.answer(for: OracleRequest(question: "Should I kill myself?", mode: .noul))
    #expect(result == .safetyIntervention(.selfHarm))
    #expect(await calls.count == 1)
  }
}

private actor SafetyBackendCalls {
  private(set) var count = 0
  func increment() { count += 1 }
}

private struct SafetyFailingBackend: OracleBackendMetadata {
  let calls: SafetyBackendCalls
  let modelIdentifier = "safety-fallback-test"
  let supportsTransientFailureFallback = true

  func predict(for prompt: DecisionPrompt) async throws -> DecisionPrediction {
    await calls.increment()
    throw URLError(.notConnectedToInternet)
  }
}
