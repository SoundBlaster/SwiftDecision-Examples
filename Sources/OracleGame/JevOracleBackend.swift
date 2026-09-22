import Foundation
import SwiftDecision
import SwiftJev

/// SwiftDecision backend adapter for the Oracle Ball domain.
///
/// The adapter keeps Jev transport and credentials outside the game engine. The
/// engine continues to receive the standard `DecisionBackend` contract, so the
/// offline fixture and Jev provider are interchangeable.
public struct JevOracleBackend: OracleBackendMetadata {
  private let backend: JevDecisionBackend
  public let modelIdentifier: String

  /// Creates a Jev-backed Oracle provider without making a network request.
  ///
  /// When `apiKey` is omitted, `TYPESAFE_API_KEY` is read by SwiftJev. Inject a
  /// `JevHTTPTransport` in tests or local fixtures to avoid live requests.
  public init(
    apiKey: String? = nil,
    model: String = "jev-latest",
    timeout: TimeInterval = 10,
    transport: any JevHTTPTransport = URLSessionJevHTTPTransport()
  ) throws {
    backend = try JevDecisionBackend(
      apiKey: apiKey,
      model: model,
      timeout: timeout,
      transport: transport)
    modelIdentifier = model
  }

  public func predict(for prompt: DecisionPrompt) async throws -> DecisionPrediction {
    try await backend.predict(for: prompt)
  }
}
