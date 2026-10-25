@testable import OracleGLiNER
import SwiftDecision
import Testing

struct OracleGLiNERWarmUpTests {
  private actor Probe: DecisionBackend {
    var prompts: [DecisionPrompt] = []
    func predict(for prompt: DecisionPrompt) async throws -> DecisionPrediction {
      prompts.append(prompt)
      // A warm-up does not require a semantically accepted answer.
      return DecisionPrediction(probabilities: [0.5, 0.5], modelIdentifier: "warm-up-fixture")
    }
  }

  @Test func warmUpUsesOneLocalDummyPredictionWithoutChangingQuestionBudget() async throws {
    let probe = Probe()
    let backend = OracleGLiNERBackend(backend: probe)
    try await backend.warmUp()
    let prompts = await probe.prompts
    #expect(prompts.count == 1)
    #expect(prompts.first?.id == "oracle.gliner.warm-up")
    #expect(prompts.first?.kind == .choice)
    #expect(backend.maximumResponseTime == 8)
  }

  @Test func warmUpFailureAndCancellationDoNotPublishAReadyBackend() async throws {
    let backend = OracleGLiNERBackend(backend: ClosureDecisionBackend { _ in throw DecisionError.timedOut })
    await #expect(throws: DecisionError.timedOut) { try await backend.warmUp() }
    let probe = Probe()
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      try await OracleGLiNERBackend(backend: probe).warmUp()
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await probe.prompts.isEmpty)
  }
}
