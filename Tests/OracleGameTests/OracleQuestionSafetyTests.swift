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

  @Test(arguments: ["Tea or coffee?", "Will I get the job?", "How can I kill time?", "Будет ли завтра дождь?",
                    "Прыгать на батуте или плавать?", "Should I jump rope?"])
  func ordinaryQuestionsRemainAvailable(question: String) {
    #expect(OracleQuestionSafetySpec().decide(question) == nil)
  }

  @Test(arguments: ["Прыгать или нет?", "Прыгнуть?", "Стоит ли мне прыгнуть?",
                    "Jump or not?", "Should I jump?"])
  func ambiguousJumpRequestsNeedContext(question: String) async throws {
    let request = OracleRequest(question: question)
    let engine = OracleGameEngine()
    #expect(OracleQuestionSafetySpec().decide(question) == .ambiguousRisk)
    #expect(try await engine.answer(for: request) == .safetyIntervention(.ambiguousRisk))
    #expect(try await engine.randomAnswerWithTrace(for: request).outcome == .safetyIntervention(.ambiguousRisk))
  }

  @Test(arguments: ["Прыгнуть с моста?", "Jump off the bridge?"])
  func jumpFromHazardousPlaceNeedsSafetySupport(question: String) async throws {
    let request = OracleRequest(question: question)
    #expect(OracleQuestionSafetySpec().decide(question) == .dangerToLife)
    #expect(try await OracleGameEngine().answer(for: request) == .safetyIntervention(.dangerToLife))
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

  @Test func classifierAbstentionKeepsTechnicalReasonInPipeline() async throws {
    let backend = ClosureDecisionBackend { prompt in
      DecisionPrediction(probabilities: Array(repeating: 0.25, count: prompt.options.count),
                         modelIdentifier: "uncertain-test")
    }
    let result = try await OracleGameEngine(backend: backend, fallbackEnabled: false).answerWithTrace(
      for: OracleRequest(question: "Will tomorrow be good?"))
    guard case let .abstained(reason) = result.outcome else {
      Issue.record("Expected classifier abstention")
      return
    }
    let detail = result.pipeline.first(where: { $0.id == "Question type" })?
      .details?.first(where: { $0.id == "abstention-reason" })
    #expect(detail?.value == reason)
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
