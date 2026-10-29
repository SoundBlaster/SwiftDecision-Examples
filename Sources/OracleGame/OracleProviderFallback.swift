import Foundation
import SpecificationCore
import SwiftDecision
#if DEBUG && ORACLE_JEV
import SwiftJev
#endif

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

  var code: String {
    switch self {
    case .cancelled: "cancelled"
    case .timedOut: "timeout"
    case .transport: "transport"
    case .rateLimited: "rateLimited"
    case .serviceUnavailable: "serviceUnavailable"
    case .circuitOpen: "circuitOpen"
    case .permanent: "providerError"
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
    #if DEBUG && ORACLE_JEV
    let category = JevFailureClassifier.classify(error)
    #else
    let engineCategory = DecisionFailureCategory.classify(error)
    let category: DecisionFailureCategory
    if engineCategory != .permanent {
      category = engineCategory
    } else if let urlError = error as? URLError {
      switch urlError.code {
      case .cancelled: category = .cancelled
      case .timedOut: category = .timedOut
      case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
           .dnsLookupFailed, .notConnectedToInternet: category = .transport
      default: category = .permanent
      }
    } else {
      category = .permanent
    }
    #endif
    switch category {
    case .cancelled: .cancelled
    case .timedOut: .timedOut
    case .transport: .transport
    case .rateLimited: .rateLimited
    case .serviceUnavailable: .serviceUnavailable
    case .permanent: .permanent
    }
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
