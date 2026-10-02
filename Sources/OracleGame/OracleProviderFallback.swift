import Foundation
import SpecificationCore
import SwiftDecision
import SwiftJev

enum OracleProviderFailure: Sendable, Equatable {
  case cancelled
  case timedOut
  case transport
  case rateLimited
  case serviceUnavailable
  case circuitOpen
  case permanent

  var isTransient: Bool {
    switch self {
    case .timedOut, .transport, .rateLimited, .serviceUnavailable, .circuitOpen:
      true
    case .cancelled, .permanent:
      false
    }
  }

  var traceLabel: String {
    switch self {
    case .cancelled: "Cancelled"
    case .timedOut: "Inference timed out"
    case .transport: "Network unavailable"
    case .rateLimited: "Provider rate limited"
    case .serviceUnavailable: "Provider temporarily unavailable"
    case .circuitOpen: "Provider cooldown active"
    case .permanent: "Non-transient provider error"
    }
  }

  var userFacingReason: String {
    oracleLocalized("Jev unavailable; an offline answer was used.")
  }

  static func classify(_ error: any Error) -> Self {
    if error is CancellationError { return .cancelled }
    if let decisionError = error as? DecisionError,
       case .timedOut = decisionError
    {
      return .timedOut
    }
    if let urlError = error as? URLError {
      switch urlError.code {
      case .cancelled:
        return .cancelled
      case .timedOut:
        return .timedOut
      case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
        .dnsLookupFailed, .notConnectedToInternet:
        return .transport
      default:
        return .permanent
      }
    }
    if let providerError = error as? JevDecisionBackendError,
       case let .httpFailure(statusCode) = providerError
    {
      if statusCode == 429 { return .rateLimited }
      if statusCode == 408 || statusCode == 425 || (500 ..< 600).contains(statusCode) {
        return .serviceUnavailable
      }
    }
    return .permanent
  }
}

struct OracleProviderFallbackContext: Sendable {
  let providerSupportsFallback: Bool
  let failure: OracleProviderFailure
}

struct OracleProviderFallbackSpec: Specification {
  func isSatisfiedBy(_ context: OracleProviderFallbackContext) -> Bool {
    PredicateSpec<OracleProviderFallbackContext>(
      description: "oracle.provider.offline-fallback-on-transient-failure") {
        $0.providerSupportsFallback && $0.failure.isTransient
      }
      .isSatisfiedBy(context)
  }
}

actor OracleProviderCircuitBreaker {
  private let cooldown: TimeInterval = 30
  private var retryAfter: Date?

  var isCoolingDown: Bool {
    guard let retryAfter else { return false }
    if Date() < retryAfter { return true }
    self.retryAfter = nil
    return false
  }

  func recordTransientFailure() {
    retryAfter = Date().addingTimeInterval(cooldown)
  }

  func recordSuccess() {
    retryAfter = nil
  }
}
