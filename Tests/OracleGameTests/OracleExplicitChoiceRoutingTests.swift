import Foundation
import Testing
@testable import OracleGame
import SwiftDecision

struct OracleExplicitChoiceRoutingTests {
  @Test(arguments: [
    ("Hello or Kitty?", ["Hello", "Kitty"]),
    ("Hello или Kitty?", ["Hello", "Kitty"]),
    ("Choose between tea and coffee", ["tea", "coffee"]),
    ("Which should I choose: tea, coffee, juice, water, or soda?",
      ["tea", "coffee", "juice", "water", "soda"])
  ])
  func validAlternativesSkipIntentClassification(question: String, options: [String]) async throws {
    let recorder = ChoiceRoutingPrompts()
    let backend = ClosureDecisionBackend { prompt in
      await recorder.record(prompt)
      // A misclassifying model must never get to override explicit alternatives.
      if prompt.options.first?.description.hasPrefix("noul:") == true {
        return DecisionPrediction(probabilities: [0.9, 0.04, 0.03, 0.03], modelIdentifier: "fixture")
      }
      return DecisionPrediction(
        probabilities: prompt.options.indices.map { $0 == 1 ? 1 : 0 }, modelIdentifier: "fixture")
    }
    let result = try await OracleGameEngine(backend: backend, fallbackEnabled: false)
      .answerWithTrace(for: OracleRequest(question: question))
    guard case let .accepted(answer) = result.outcome else {
      Issue.record("Expected an accepted Choice answer")
      return
    }
    #expect(answer.mode == .choice)
    #expect(answer.displayText == options[1])
    let prompts = await recorder.prompts
    #expect(prompts.count == 1)
    #expect(prompts.first?.kind == .choice)
    #expect(prompts.first?.options.map(\.description) == options)
    #expect(!result.pipeline.contains { $0.id == "Question type" })
    #expect(result.pipeline.first { $0.id == "Request routing" }?.summary == "Choice")
  }

  @Test(arguments: [
    ("Choose the star: Hello or Sun", "Choose the star", "No additional observations.", ["Hello", "Sun"]),
    ("Выбери животное: квадрат или собака", "Выбери животное", "No additional observations.", ["квадрат", "собака"]),
    ("Hello or Kitty?", "Hello or Kitty?", "Hello or Kitty?", ["Hello", "Kitty"]),
    (": Tea or Coffee?", ": Tea or Coffee?", ": Tea or Coffee?", ["Tea", "Coffee"])
  ])
  func criterionAndAlternativesRemainSeparate(
    question: String, instructions: String, context: String, options: [String]
  ) async throws {
    let recorder = ChoiceRoutingPrompts()
    let backend = ClosureDecisionBackend { prompt in
      await recorder.record(prompt)
      return DecisionPrediction(probabilities: [0, 1], modelIdentifier: "fixture")
    }
    _ = try await OracleGameEngine(backend: backend, fallbackEnabled: false)
      .answer(for: OracleRequest(question: question))
    let prompts = await recorder.prompts
    #expect(prompts.count == 1)
    #expect(prompts.first?.instructions == instructions)
    #expect(prompts.first?.context == context)
    #expect(prompts.first?.options.map(\.description) == options)
  }

  @Test
  func explicitNoulModeOverridesExtractedAlternatives() async throws {
    let recorder = ChoiceRoutingPrompts()
    let backend = ClosureDecisionBackend { prompt in
      await recorder.record(prompt)
      return DecisionPrediction(probabilities: [0, 1], modelIdentifier: "fixture")
    }
    let result = try await OracleGameEngine(backend: backend, fallbackEnabled: false)
      .answer(for: OracleRequest(question: "Hello or Kitty?", mode: .noul))
    guard case let .accepted(answer) = result else {
      Issue.record("Expected the explicitly requested Noul answer")
      return
    }
    #expect(answer.mode == .noul)
    let prompts = await recorder.prompts
    #expect(prompts.map(\.kind) == [.noul])
  }

  @Test(arguments: [
    "How likely am I to win or lose?",
    "Какова вероятность победы или поражения?"
  ])
  func probabilityQuestionStillUsesTheClassifier(question: String) async throws {
    let recorder = ChoiceRoutingPrompts()
    let backend = ClosureDecisionBackend { prompt in
      await recorder.record(prompt)
      return DecisionPrediction(
        probabilities: prompt.kind == .choice ? [0, 0, 1, 0] : [0, 0, 0, 1],
        modelIdentifier: "fixture")
    }
    let result = try await OracleGameEngine(backend: backend, fallbackEnabled: false)
      .answerWithTrace(for: OracleRequest(question: question))
    guard case let .accepted(answer) = result.outcome else {
      Issue.record("Expected a Score answer")
      return
    }
    #expect(answer.mode == .score)
    let prompts = await recorder.prompts
    #expect(prompts.map(\.kind) == [.choice, .score])
    #expect(result.pipeline.contains { $0.id == "Question type" })
  }

  @Test
  func invalidAlternativesDoNotBypassClassification() async throws {
    let recorder = ChoiceRoutingPrompts()
    let backend = ClosureDecisionBackend { prompt in
      await recorder.record(prompt)
      return DecisionPrediction(probabilities: [0, 0, 0, 1], modelIdentifier: "fixture")
    }
    let result = try await OracleGameEngine(backend: backend, fallbackEnabled: false)
      .answerWithTrace(for: OracleRequest(question: String(repeating: "a", count: 81) + " or Kitty?"))
    guard case let .fallback(answer, _) = result.outcome else {
      Issue.record("Expected unsupported output after classification")
      return
    }
    #expect(answer.mode == .unsupported)
    let prompts = await recorder.prompts
    #expect(prompts.count == 1)
    #expect(prompts.first?.options.count == 4)
    #expect(result.pipeline.contains { $0.id == "Question type" })
  }
}

private actor ChoiceRoutingPrompts {
  private(set) var prompts: [DecisionPrompt] = []
  func record(_ prompt: DecisionPrompt) { prompts.append(prompt) }
}
