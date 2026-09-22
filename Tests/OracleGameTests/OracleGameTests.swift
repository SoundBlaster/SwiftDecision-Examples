import XCTest
@testable import OracleGame
import SwiftDecision

final class OracleGameTests: XCTestCase {
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
}
