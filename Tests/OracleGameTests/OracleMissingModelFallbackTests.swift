import OracleGame
import Testing

@Test func onlyMissingSelectedLocalModelEnablesRandomFallback() {
  let spec = OracleMissingModelFallbackSpec()
  for selected in [false, true] {
    for installed in [false, true] {
      for preparing in [false, true] {
        #expect(spec.isSatisfiedBy(.init(
          localModelSelected: selected, modelInstalled: installed, preparingModel: preparing))
          == (selected && !installed && !preparing))
      }
    }
  }
}

@Test func missingModelSimulationReturnsAnExplicitSimulatedAnswerAndTrace() async throws {
  let result = try await OracleGameEngine().randomAnswerWithTrace()
  guard case let .accepted(answer) = result.outcome else {
    Issue.record("Expected a simulated answer")
    return
  }
  #expect(!answer.displayText.isEmpty)
  guard case .simulated = answer.source else {
    Issue.record("A random answer must not be attributed to a model")
    return
  }
  #expect(!result.pipeline.isEmpty)
}
