import Foundation
import XCTest
@testable import OracleGame
import SwiftDecision
import SwiftJev

final class OracleProviderFallbackTests: XCTestCase {
  func testTimeoutUsesAnOfflineAnswerAndRecordsFallback() async throws {
    let engine = OracleGameEngine(backend: FailingOracleBackend(
      failure: .timeout,
      requestCount: RequestCount()))

    let result = try await engine.answerWithTrace(
      for: OracleRequest(question: "Will it work?"))

    guard case let .fallback(answer, reason) = result.outcome else {
      return XCTFail("expected an offline fallback")
    }
    XCTAssertEqual(answer.source, .offlineFixture)
    XCTAssertTrue(reason.contains("offline answer"))
    XCTAssertEqual(result.pipeline.last?.title, "Provider fallback")
  }

  func testCooldownSkipsFurtherRequestsAfterTemporaryProviderFailure() async throws {
    let requestCount = RequestCount()
    let engine = OracleGameEngine(backend: FailingOracleBackend(
      failure: .unavailable,
      requestCount: requestCount))

    let first = try await engine.answer(for: OracleRequest(question: "Will it work?"))
    let second = try await engine.answer(for: OracleRequest(question: "Will it rain?"))

    guard case .fallback = first, case .fallback = second else {
      return XCTFail("expected offline fallback answers")
    }
    let actualRequestCount = await requestCount.value
    XCTAssertEqual(actualRequestCount, 1)
  }

  func testPermanentProviderFailureDoesNotUseOfflineFallback() async {
    let engine = OracleGameEngine(backend: FailingOracleBackend(
      failure: .permanent,
      requestCount: RequestCount()))

    do {
      _ = try await engine.answer(for: OracleRequest(question: "Will it work?"))
      XCTFail("expected the permanent provider error")
    } catch let error as JevDecisionBackendError {
      XCTAssertEqual(error, .httpFailure(statusCode: 400))
    } catch {
      XCTFail("unexpected error: \(error)")
    }
  }

  func testPermanentURLErrorDoesNotUseOfflineFallback() async {
    let engine = OracleGameEngine(backend: FailingOracleBackend(
      failure: .permanentURLFailure,
      requestCount: RequestCount()))

    do {
      _ = try await engine.answer(for: OracleRequest(question: "Will it work?"))
      XCTFail("expected the permanent URL error")
    } catch let error as URLError {
      XCTAssertEqual(error.code, .serverCertificateUntrusted)
    } catch {
      XCTFail("unexpected error: \(error)")
    }
  }

  func testFallbackSpecificationRequiresTransientFailureAndEnabledProvider() {
    let specification = OracleProviderFallbackSpec()

    XCTAssertTrue(specification.isSatisfiedBy(.init(
      providerSupportsFallback: true,
      failure: .timedOut)))
    XCTAssertFalse(specification.isSatisfiedBy(.init(
      providerSupportsFallback: true,
      failure: .permanent)))
    XCTAssertFalse(specification.isSatisfiedBy(.init(
      providerSupportsFallback: false,
      failure: .transport)))
    XCTAssertFalse(specification.isSatisfiedBy(.init(
      providerSupportsFallback: true,
      failure: .cancelled)))
    XCTAssertEqual(OracleProviderFailure.classify(DecisionError.timedOut), .timedOut)
    XCTAssertEqual(OracleProviderFailure.classify(URLError(.notConnectedToInternet)), .transport)
    XCTAssertEqual(OracleProviderFailure.classify(URLError(.networkConnectionLost)), .transport)
    XCTAssertEqual(OracleProviderFailure.classify(URLError(.cancelled)), .cancelled)
    for code: URLError.Code in [.serverCertificateUntrusted, .badURL, .userAuthenticationRequired] {
      XCTAssertEqual(OracleProviderFailure.classify(URLError(code)), .permanent)
    }
    XCTAssertEqual(
      OracleProviderFailure.classify(JevDecisionBackendError.httpFailure(statusCode: 429)),
      .rateLimited)
  }
}

private enum FailingBackendMode: Sendable {
  case timeout
  case unavailable
  case permanent
  case permanentURLFailure
}

private struct FailingOracleBackend: OracleBackendMetadata {
  let failure: FailingBackendMode
  let requestCount: RequestCount
  let modelIdentifier = "jev-test"
  let supportsTransientFailureFallback = true

  func predict(for prompt: DecisionPrompt) async throws -> DecisionPrediction {
    await requestCount.increment()
    switch failure {
    case .timeout:
      throw DecisionError.timedOut
    case .unavailable:
      throw JevDecisionBackendError.httpFailure(statusCode: 503)
    case .permanent:
      throw JevDecisionBackendError.httpFailure(statusCode: 400)
    case .permanentURLFailure:
      throw URLError(.serverCertificateUntrusted)
    }
  }
}

private actor RequestCount {
  private(set) var value = 0

  func increment() {
    value += 1
  }
}
