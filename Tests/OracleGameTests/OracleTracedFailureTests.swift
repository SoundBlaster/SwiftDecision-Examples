import Foundation
import OracleGame
import SwiftDecision
import Testing

struct OracleTracedFailureTests {
  private struct TimeoutBackend: OracleBackendMetadata {
    let modelIdentifier = "local-timeout-fixture"
    func predict(for prompt: DecisionPrompt) async throws -> DecisionPrediction {
      if prompt.options.count == 4 {
        return DecisionPrediction(probabilities: [0.97, 0.01, 0.01, 0.01], modelIdentifier: modelIdentifier)
      }
      throw DecisionError.timedOut
    }
  }

  @Test func failedChoiceRetainsRoutingAndTheFailedCoreDecisionTrace() async throws {
    let engine = OracleGameEngine(backend: TimeoutBackend(), fallbackEnabled: false)
    do {
      _ = try await engine.answerWithTrace(for: OracleRequest(question: "День или ночь"), capturingFailures: true)
      Issue.record("Expected a captured timeout")
    } catch let failure as OracleTracedFailure {
      #expect(failure.kind == "timeout")
      #expect(failure.mode == .choice)
      #expect(failure.provider == "local-timeout-fixture")
      #expect(failure.pipeline.map(\.title) == ["Question eligibility", "Choice alternatives", "Request routing", "Answer decision"])
      let stage = try #require(failure.pipeline.last)
      #expect(stage.summary == "Request failed")
      #expect(stage.distribution == nil)
      #expect(stage.decisionEvents.contains { $0.stage == "Inference started" })
      #expect(!stage.decisionEvents.contains { $0.stage == "Inference completed" })
      #expect(stage.specificationEvents.contains { $0.name == "backend prediction" && $0.outcome.hasPrefix("Failed") })
      #expect(!(stage.orderedTrace?.isEmpty ?? true))
    }
  }

  @Test func completedIntentSurvivesAFailedAnswer() async throws {
    let engine = OracleGameEngine(backend: TimeoutBackend(), fallbackEnabled: false)
    do {
      _ = try await engine.answerWithTrace(for: OracleRequest(question: "Will it work?"), capturingFailures: true)
      Issue.record("Expected a captured timeout")
    } catch let failure as OracleTracedFailure {
      #expect(failure.mode == .noul)
      let intent = try #require(failure.pipeline.first { $0.title == "Question type" })
      #expect(intent.distribution?.probabilities == [0.97, 0.01, 0.01, 0.01])
      #expect(failure.pipeline.last?.title == "Answer decision")
      #expect(Set(failure.pipeline.map(\.id)).count == failure.pipeline.count)
    }
  }

  @Test func classifierFailureHasItsOwnStageAndDoesNotExportErrorBody() async throws {
    struct SecretError: Error, CustomStringConvertible {
      var description: String { "Authorization: Bearer private-test-credential" }
    }
    let backend = ClosureDecisionBackend { _ in throw SecretError() }
    do {
      _ = try await OracleGameEngine(backend: backend, fallbackEnabled: false).answerWithTrace(
        for: OracleRequest(question: "Will it work?"), capturingFailures: true)
      Issue.record("Expected a captured error")
    } catch let failure as OracleTracedFailure {
      #expect(failure.kind == "providerError")
      #expect(failure.pipeline.last?.title == "Question type")
      let data = try JSONEncoder().encode(failure.pipeline)
      #expect(!String(decoding: data, as: UTF8.self).contains("private-test-credential"))
    }
  }

  @Test func defaultErrorContractAndCancellationAreNotWrapped() async throws {
    await #expect(throws: DecisionError.timedOut) {
      try await OracleGameEngine(backend: TimeoutBackend(), fallbackEnabled: false)
        .answerWithTrace(for: OracleRequest(question: "red or blue?"))
    }
    let cancelled = ClosureDecisionBackend { _ in throw CancellationError() }
    await #expect(throws: CancellationError.self) {
      try await OracleGameEngine(backend: cancelled, fallbackEnabled: false)
        .answerWithTrace(for: OracleRequest(question: "red or blue?"), capturingFailures: true)
    }
  }

  @Test func disabledTracingStillRecordsFailureWithoutInventedEvents() async throws {
    let engine = OracleGameEngine(backend: TimeoutBackend(), configuration: .init(traceMode: .disabled), fallbackEnabled: false)
    do {
      _ = try await engine.answerWithTrace(for: OracleRequest(question: "red or blue?"), capturingFailures: true)
      Issue.record("Expected a captured timeout")
    } catch let failure as OracleTracedFailure {
      let stage = try #require(failure.pipeline.last)
      #expect(stage.decisionEvents.isEmpty && stage.specificationEvents.isEmpty)
      #expect(stage.orderedTrace == nil)
    }
  }
}
