import Foundation
import XCTest
@testable import OracleGame
import SwiftDecision
import SwiftJev

final class OracleGameTests: XCTestCase {
  func testAutomaticRoutingChoosesNoulForBooleanQuestion() async throws {
    let engine = OracleGameEngine()
    let outcome = try await engine.answer(for: OracleRequest(question: "Will it work?"))

    guard case let .accepted(answer) = outcome else {
      return XCTFail("expected accepted answer")
    }
    XCTAssertEqual(answer.mode, .noul)
  }

  func testAutomaticRoutingChoosesScoreForProbabilityQuestion() async throws {
    let engine = OracleGameEngine()
    let outcome = try await engine.answer(for: OracleRequest(question: "How likely is success?"))

    guard case let .accepted(answer) = outcome else {
      return XCTFail("expected accepted answer")
    }
    XCTAssertEqual(answer.mode, .score)
    XCTAssertEqual(answer.displayText, "83%")
  }

  func testAutomaticRoutingBuildsChoiceOptionsFromQuestion() async throws {
    let engine = OracleGameEngine()
    let outcome = try await engine.answer(for: OracleRequest(question: "Which is better: tea or coffee?"))

    guard case let .accepted(answer) = outcome else {
      return XCTFail("expected accepted answer")
    }
    XCTAssertEqual(answer.mode, .choice)
    XCTAssertEqual(answer.displayText, "tea")
  }

  func testAutomaticRoutingRecognizesDirectAlternatives() async throws {
    let engine = OracleGameEngine()
    let outcome = try await engine.answer(for: OracleRequest(question: "Tea or Coffee?"))

    guard case let .accepted(answer) = outcome else {
      return XCTFail("expected accepted answer")
    }
    XCTAssertEqual(answer.mode, .choice)
    XCTAssertEqual(answer.displayText, "Tea")
  }

  func testAutomaticRoutingUsesUnsupportedFallbackForFactualQuestion() async throws {
    let engine = OracleGameEngine()
    let outcome = try await engine.answer(
      for: OracleRequest(question: "What is the capital of Paris?"))

    guard case let .fallback(answer, reason) = outcome else {
      return XCTFail("expected unsupported fallback")
    }
    XCTAssertEqual(answer.mode, .unsupported)
    XCTAssertTrue(OracleUnsupportedResponses.messages.contains(answer.displayText))
    XCTAssertTrue(reason.contains("outside the supported answer types"))
  }

  func testUnsupportedRouteDoesNotInventChoiceOptionsOrMakeSecondRequest() async throws {
    let recorder = PromptRecorder()
    let backend = ClosureDecisionBackend { prompt in
      await recorder.record(prompt)
      return DecisionPrediction(
        probabilities: [0.01, 0.01, 0.01, 0.97],
        modelIdentifier: "intent-fixture")
    }
    let engine = OracleGameEngine(backend: backend)

    let outcome = try await engine.answer(
      for: OracleRequest(question: "What is the capital of Paris?"))

    guard case let .fallback(answer, _) = outcome else {
      return XCTFail("expected unsupported fallback")
    }
    XCTAssertEqual(answer.mode, .unsupported)
    let prompts = await recorder.prompts
    XCTAssertEqual(prompts.count, 1)
    XCTAssertEqual(prompts[0].kind, .choice)
    XCTAssertEqual(prompts[0].options.count, 4)
    XCTAssertTrue(prompts[0].instructions.contains("Never invent Choice options"))
  }

  func testAutomaticIntentAbstentionRemainsDistinctWhenFallbackIsDisabled() async throws {
    let backend = ClosureDecisionBackend { prompt in
      DecisionPrediction(
        probabilities: Array(repeating: 0.25, count: prompt.options.count),
        modelIdentifier: "low-confidence-intent")
    }
    let engine = OracleGameEngine(backend: backend, fallbackEnabled: false)

    let outcome = try await engine.answer(
      for: OracleRequest(question: "What is the capital of Paris?"))

    guard case let .abstained(reason) = outcome else {
      return XCTFail("expected classifier abstention")
    }
    XCTAssertTrue(reason.contains("confidence"))
  }

  func testOfflineClassifierRejectsOpenEndedAndMalformedQuestions() async throws {
    let engine = OracleGameEngine()

    for question in ["Why is the sky blue?", "Write a poem", "asdf"] {
      let outcome = try await engine.answer(for: OracleRequest(question: question))
      guard case let .fallback(answer, _) = outcome else {
        return XCTFail("expected unsupported fallback for \(question)")
      }
      XCTAssertEqual(answer.mode, .unsupported)
      XCTAssertTrue(OracleUnsupportedResponses.messages.contains(answer.displayText))
    }
  }

  func testExplicitUnsupportedModeDoesNotInvokeAutomaticRouting() async throws {
    let engine = OracleGameEngine()
    let outcome = try await engine.answer(
      for: OracleRequest(question: "Will this work?", mode: .unsupported))

    guard case let .fallback(answer, reason) = outcome else {
      return XCTFail("expected explicit unsupported fallback")
    }
    XCTAssertEqual(answer.mode, .unsupported)
    XCTAssertTrue(OracleUnsupportedResponses.messages.contains(answer.displayText))
    XCTAssertTrue(reason.contains("unsupported answer mode requested"))
  }

  func testUnsupportedResponsesOfferSeveralDistinctPhrases() {
    XCTAssertGreaterThanOrEqual(OracleUnsupportedResponses.messages.count, 5)
    XCTAssertEqual(
      Set(OracleUnsupportedResponses.messages).count,
      OracleUnsupportedResponses.messages.count)
  }

  func testChoicePlannerAcceptsUpToFiveCommaSeparatedOptions() {
    let plan = OracleChoicePlanner.plan(for: "Which should I choose: tea, coffee, juice, water, or soda?")

    XCTAssertEqual(plan.options, ["tea", "coffee", "juice", "water", "soda"])
  }

  func testChoicePlannerAcceptsBetweenAndAlternatives() {
    let plan = OracleChoicePlanner.plan(for: "Choose between tea and coffee")

    XCTAssertEqual(plan.options, ["tea", "coffee"])
  }

  func testChoicePlannerPreservesChoiceCasing() {
    let plan = OracleChoicePlanner.plan(for: "Should I choose SwiftUI or UIKit?")

    XCTAssertEqual(plan.options, ["SwiftUI", "UIKit"])
  }

  func testChoicePlannerRecognizesRussianAlternatives() {
    let plan = OracleChoicePlanner.plan(for: "Чай или кофе?")

    XCTAssertEqual(plan.options, ["Чай", "кофе"])
  }

  func testChoicePlannerRemovesInterrogativePrefixBeforeAlternatives() {
    let plan = OracleChoicePlanner.plan(for: "Who is president of US trump or Putin?")

    XCTAssertEqual(plan.options, ["trump", "Putin"])
  }

  func testOfflineNoulUsesAcceptedSpecRoute() async throws {
    let engine = OracleGameEngine()
    let outcome = try await engine.answer(for: OracleRequest(question: "Will it work?", mode: .noul))

    guard case let .accepted(answer) = outcome else {
      return XCTFail("expected accepted answer")
    }
    XCTAssertEqual(answer.mode, .noul)
    XCTAssertEqual(answer.displayText, "Definitely\nyes")
    XCTAssertEqual(answer.source, .offlineFixture)
  }

  func testModePoliciesProduceTypedDisplayAnswers() async throws {
    let engine = OracleGameEngine()
    let choice = try await engine.answer(for: OracleRequest(question: "Should I wait?", mode: .choice))
    let score = try await engine.answer(for: OracleRequest(question: "How likely?", mode: .score))

    guard case let .accepted(choiceAnswer) = choice else { return XCTFail("choice did not accept") }
    guard case let .accepted(scoreAnswer) = score else { return XCTFail("score did not accept") }
    XCTAssertEqual(choiceAnswer.displayText, "Ask again\nlater")
    XCTAssertEqual(scoreAnswer.displayText, "83%")
  }

  func testInvalidQuestionIsRejectedByEligibilitySpec() async {
    let engine = OracleGameEngine()
    do {
      _ = try await engine.answer(for: OracleRequest(question: "   ", mode: .noul))
      XCTFail("expected invalid question")
    } catch let error as OracleGameError {
      XCTAssertEqual(error, .invalidQuestion)
    } catch {
      XCTFail("unexpected error: \(error)")
    }
  }

  func testProviderErrorsRemainErrors() async {
    struct ExpectedError: Error {}
    let backend = ClosureDecisionBackend { _ in throw ExpectedError() }
    let engine = OracleGameEngine(backend: backend)

    do {
      _ = try await engine.answer(for: OracleRequest(question: "Fail", mode: .noul))
      XCTFail("expected provider error")
    } catch is ExpectedError {
      // The outcome router must not turn thrown errors into abstention.
    } catch {
      XCTFail("unexpected error: \(error)")
    }
  }

  func testAbstentionKeepsTheDecisionReason() async throws {
    let backend = ClosureDecisionBackend { prompt in
      DecisionPrediction(
        probabilities: Array(repeating: 0.5, count: prompt.options.count),
        modelIdentifier: "low-confidence")
    }
    let engine = OracleGameEngine(
      backend: backend,
      configuration: .init(
        policies: .init(
          noul: .init(minimumProbability: 0.9, minimumConfidence: 0),
          choice: .init(minimumProbability: 0.9, minimumConfidence: 0),
          score: .init(minimumProbability: 0.9, minimumConfidence: 0))),
      fallbackEnabled: false)

    let outcome = try await engine.answer(for: OracleRequest(question: "Maybe?", mode: .noul))
    guard case let .abstained(reason) = outcome else {
      return XCTFail("expected abstention")
    }
    XCTAssertTrue(reason.contains("confidence"))
  }

  func testFallbackRemainsDistinctFromAcceptance() async throws {
    let backend = ClosureDecisionBackend { prompt in
      DecisionPrediction(
        probabilities: Array(repeating: 0.5, count: prompt.options.count),
        modelIdentifier: "low-confidence")
    }
    let engine = OracleGameEngine(
      backend: backend,
      configuration: .init(
        policies: .init(
          noul: .init(minimumProbability: 0.9, minimumConfidence: 0),
          choice: .init(minimumProbability: 0.9, minimumConfidence: 0),
          score: .init(minimumProbability: 0.9, minimumConfidence: 0))))

    let outcome = try await engine.answer(for: OracleRequest(question: "Fallback?", mode: .noul))
    guard case let .fallback(answer, reason) = outcome else {
      return XCTFail("expected fallback")
    }
    XCTAssertEqual(answer.displayText, "Definitely\nyes")
    XCTAssertTrue(reason.contains("confidence"))
  }

  func testBackendProvenanceSurvivesDisabledTracing() async throws {
    struct NamedBackend: OracleBackendMetadata {
      let modelIdentifier = "jev-audit-model"

      func predict(for prompt: DecisionPrompt) async throws -> DecisionPrediction {
        DecisionPrediction(
          probabilities: prompt.kind == .noul ? [0.1, 0.9] : [0.1, 0.9, 0],
          modelIdentifier: modelIdentifier)
      }
    }
    let engine = OracleGameEngine(
      backend: NamedBackend(),
      configuration: .init(traceMode: .disabled))

    let outcome = try await engine.answer(for: OracleRequest(question: "Who?", mode: .noul))
    guard case let .accepted(answer) = outcome else { return XCTFail("expected accepted answer") }
    XCTAssertEqual(answer.source, .model(identifier: "jev-audit-model"))
  }

  func testJevAdapterUsesInjectedTransportWithoutLiveNetworking() async throws {
    let responseBody = try JSONSerialization.data(withJSONObject: [
      "model": "jev-fixture",
      "answers": [
        "swiftdecision": [
          "type": "noul",
          "noul": 0.9,
        ]
      ]
    ])
    let transport = FixtureJevTransport(response: JevHTTPResponse(statusCode: 200, body: responseBody))
    let backend = try JevOracleBackend(
      apiKey: "fixture-key",
      model: "jev-test",
      transport: transport)
    let engine = OracleGameEngine(backend: backend)

    let outcome = try await engine.answer(for: OracleRequest(question: "Is this a fixture?", mode: .noul))
    guard case let .accepted(answer) = outcome else { return XCTFail("expected accepted Jev answer") }
    XCTAssertEqual(answer.source, .model(identifier: "jev-test"))
    let requests = await transport.requests
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(requests[0].headers["Authorization"], "Bearer fixture-key")
  }
}

private actor FixtureJevTransport: JevHTTPTransport {
  let response: JevHTTPResponse
  var requests: [JevHTTPRequest] = []

  init(response: JevHTTPResponse) {
    self.response = response
  }

  func send(_ request: JevHTTPRequest) async throws -> JevHTTPResponse {
    requests.append(request)
    return response
  }
}

private actor PromptRecorder {
  private(set) var prompts: [DecisionPrompt] = []

  func record(_ prompt: DecisionPrompt) {
    prompts.append(prompt)
  }
}
