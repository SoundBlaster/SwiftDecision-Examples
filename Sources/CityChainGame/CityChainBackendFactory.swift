import SwiftDecision
import SwiftJev

/// Provider construction for the City Chain example.
///
/// The app keeps its offline backend by default. Call ``makeJev(apiKey:)`` from an explicit
/// development or production configuration when hosted Jev inference is desired.
public enum CityChainBackendFactory {
  /// Creates the hosted TypeSafe Jev backend without making a network request.
  ///
  /// Pass `apiKey` explicitly for app-owned secret injection, or omit it to read
  /// `TYPESAFE_API_KEY` from the process environment during local development.
  public static func makeJev(
    apiKey: String? = nil,
    transport: any SwiftJev.JevHTTPTransport = SwiftJev.URLSessionJevHTTPTransport()
  ) throws -> any DecisionBackend {
    try SwiftJev.JevDecisionBackend(apiKey: apiKey, transport: transport)
  }
}
