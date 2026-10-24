import Foundation
import FoundationModels
import OracleGame
import SwiftDecision

/// Availability is checked again before each request and when the app becomes active.
enum OracleAppleIntelligenceStatus {
  static func failureMessage(for error: any Error) -> String {
    if let unavailableMessage { return unavailableMessage }
    if let decisionError = error as? DecisionError, decisionError == .timedOut {
      return String(localized: "Apple Intelligence took too long. Try again.")
    }
    return String(localized: "Apple Intelligence could not return a valid decision. Try again or choose another provider.")
  }

  static var unavailableMessage: String? {
    switch AppleIntelligenceOracleBackend.availability {
    case .available: nil
    case .unavailable(.deviceNotEligible):
      String(localized: "Apple Intelligence is not supported on this device.")
    case .unavailable(.appleIntelligenceNotEnabled):
      String(localized: "Enable Apple Intelligence in system settings.")
    case .unavailable(.modelNotReady):
      String(localized: "The Apple Intelligence model is still downloading or preparing.")
    case .unavailable:
      String(localized: "Apple Intelligence is currently unavailable.")
    }
  }
}
