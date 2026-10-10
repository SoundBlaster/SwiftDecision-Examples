import Foundation
import XCTest
@testable import OracleGame
import SwiftDecision
import SwiftJev

final class OracleProviderFallbackTests: XCTestCase {
  func testJevResponseBudgetBoundsAnInjectedSlowTransport() async throws {
    let backend = try JevOracleBackend(
      apiKey: "fixture-key", timeout: 0.05, transport: SlowJevTransport())
    let result = try await OracleGameEngine(backend: backend).answerWithTrace(
      for: OracleRequest(question: "Will it work?", mode: .noul))
    guard case let .fallback(answer, _) = result.outcome else {
      return XCTFail("expected deadline fallback before the slow transport responds")
    }
    XCTAssertEqual(answer.source, .offlineFixture)
    XCTAssertEqual(result.pipeline.last?.details?.last?.value, "Inference timed out")
  }

  func testNearTieJevClassificationReachesTheDecisionPolicy() async throws {
    let backend = try JevOracleBackend(apiKey: "fixture-key", transport: NearTieJevTransport())
    // A rejected near-tie response is a permanent provider error, so this would throw.
    let result = try await OracleGameEngine(backend: backend).answerWithTrace(
      for: OracleRequest(question: "Will it work?"))
    XCTAssertNotNil(result.pipeline.first(where: { $0.id == "Question type" }))
  }

  func testSuccessfulLiveClassificationSurvivesAnAnswerFailure() async throws {
    let engine = OracleGameEngine(backend: RoutedFailureBackend())
    let result = try await engine.answerWithTrace(
      for: OracleRequest(question: "Какова вероятность успеха?"))
    guard case let .fallback(answer, _) = result.outcome else {
      return XCTFail("expected offline fallback")
    }
    XCTAssertEqual(answer.mode, .score)
    XCTAssertEqual(answer.source, .offlineFixture)
    XCTAssertEqual(result.pipeline.first(where: { $0.id == "Question type" })?.summary, "Score · 97%")
    XCTAssertEqual(Set(result.pipeline.map(\.id)).count, result.pipeline.count)
  }

  func testClassificationAndAnswerShareOneResponseBudget() async throws {
    let result = try await OracleGameEngine(backend: SharedBudgetBackend()).answer(
      for: OracleRequest(question: "Will it work?"))
    guard case let .fallback(answer, _) = result else {
      return XCTFail("separate per-call timeouts would incorrectly accept both slow calls")
    }
    XCTAssertEqual(answer.mode, .noul)
  }

  func testCancellationDuringDeadlineWaitRemainsCancellation() async throws {
    let backend = try JevOracleBackend(
      apiKey: "fixture-key", timeout: 1, transport: SlowJevTransport())
    let task = Task {
      try await OracleGameEngine(backend: backend).answer(
        for: OracleRequest(question: "Will it work?", mode: .noul))
    }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("cancellation must not return an offline answer")
    } catch is CancellationError {
      // Cancellation remains outside the fallback specification.
    } catch {
      XCTFail("unexpected error: \(error)")
    }
  }

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
    XCTAssertEqual(OracleProviderFailure.classify(URLError(.timedOut)), .timedOut)
    for code: URLError.Code in [.serverCertificateUntrusted, .badURL, .userAuthenticationRequired] {
      XCTAssertEqual(OracleProviderFailure.classify(URLError(code)), .permanent)
    }
    XCTAssertEqual(
      OracleProviderFailure.classify(JevDecisionBackendError.httpFailure(statusCode: 429)),
      .rateLimited)
  }
}

private struct SlowJevTransport: JevHTTPTransport {
  func send(_ request: JevHTTPRequest) async throws -> JevHTTPResponse {
    try await Task.sleep(nanoseconds: 300_000_000)
    return JevHTTPResponse(statusCode: 200, body: Data(
      #"{"model":"fixture","answers":{"swiftdecision":{"type":"noul","noul":0.9}}}"#.utf8))
  }
}

private struct RoutedFailureBackend: OracleBackendMetadata {
  let modelIdentifier = "routed-failure-fixture"
  let supportsTransientFailureFallback = true

  func predict(for prompt: DecisionPrompt) async throws -> DecisionPrediction {
    if prompt.kind == .choice {
      return DecisionPrediction(probabilities: [0.01, 0.01, 0.97, 0.01], modelIdentifier: modelIdentifier)
    }
    throw URLError(.timedOut)
  }
}

private struct SharedBudgetBackend: OracleBackendMetadata {
  let modelIdentifier = "shared-budget-fixture"
  let supportsTransientFailureFallback = true
  let maximumResponseTime: TimeInterval? = 0.65

  func predict(for prompt: DecisionPrompt) async throws -> DecisionPrediction {
    try await Task.sleep(nanoseconds: 400_000_000)
    return DecisionPrediction(
      probabilities: prompt.kind == .choice ? [0.97, 0.01, 0.01, 0.01] : [0.1, 0.9],
      modelIdentifier: modelIdentifier)
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

/// Answers the intent classifier with a near tie where the returned `choice` label is
/// 0.01 below the highest probability, as the TypeSafe API can do.
private struct NearTieJevTransport: JevHTTPTransport {
  func send(_ request: JevHTTPRequest) async throws -> JevHTTPResponse {
    let payload = try JSONSerialization.jsonObject(with: request.body) as? [String: Any]
    let questions = payload?["questions"] as? [String: [String: Any]]
    let question = questions?["swiftdecision"] ?? [:]
    let answer: [String: Any]
    if question["type"] as? String == "choice" {
      let ids = ((question["criteria"] as? [String: String]) ?? [:]).keys.sorted()
      let rest = 0.01 / Double(max(ids.count - 2, 1))
      var probabilities: [String: Double] = [:]
      for (index, id) in ids.enumerated() {
        probabilities[id] = index == 0 ? 0.50 : index == 1 ? 0.49 : rest
      }
      answer = [
        "type": "choice", "choice": ids[1], "confidence": 0.49, "probabilities": probabilities,
      ]
    } else {
      answer = ["type": "noul", "noul": 0.99]
    }
    return JevHTTPResponse(statusCode: 200, body: try JSONSerialization.data(withJSONObject: [
      "model": "jev-near-tie-fixture", "answers": ["swiftdecision": answer],
    ]))
  }
}
