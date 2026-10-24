#if canImport(FoundationModels)
import Foundation
import FoundationModels
import SwiftDecision

/// On-device Oracle inference. No credentials, cloud fallback, or transient-failure fallback.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public struct AppleIntelligenceOracleBackend: OracleBackendMetadata {
  private let backend: FoundationModelsDecisionBackend
  public let modelIdentifier = "apple.foundation-models.on-device"
  public let maximumResponseTime: TimeInterval?

  public init(normalizeOutput: Bool = true, timeout: TimeInterval = 15) {
    backend = FoundationModelsDecisionBackend(
      normalization: normalizeOutput ? .sumToOne : .none, strategy: .optionAssessment)
    maximumResponseTime = timeout
  }

  /// Injectable guided-generation boundary for contract tests; never contacts a provider.
  public init(
    client: any FoundationModelsDecisionClient,
    normalizeOutput: Bool = true,
    timeout: TimeInterval = 15,
    strategy: FoundationModelsDecisionBackend.Strategy = .optionAssessment
  ) {
    backend = FoundationModelsDecisionBackend(
      client: client, normalization: normalizeOutput ? .sumToOne : .none, strategy: strategy)
    maximumResponseTime = timeout
  }

  public static var availability: SystemLanguageModel.Availability {
    SystemLanguageModel.default.availability
  }

  public func predict(for prompt: DecisionPrompt) async throws -> DecisionPrediction {
    try await backend.predict(for: prompt)
  }
}
#endif
