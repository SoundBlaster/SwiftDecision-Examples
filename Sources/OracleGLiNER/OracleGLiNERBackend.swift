import Foundation
import OracleGame
import SwiftDecision
#if ORACLE_GLINER
import SwiftDecisionGLiNER
#endif

/// Local GLiNER metadata with no transient-error or cloud fallback.
public struct OracleGLiNERBackend: OracleBackendMetadata {
  private let backend: any DecisionBackend
  public let modelIdentifier = "fastino/gliner2.5-small-v1"
  public let maximumResponseTime: TimeInterval? = 8

  /// Creates an adapter around the native runtime or an injected test backend.
  public init(backend: any DecisionBackend) { self.backend = backend }

  public func predict(for prompt: DecisionPrompt) async throws -> DecisionPrediction {
    try await backend.predict(for: prompt)
  }

  public static var isSupportedBuild: Bool {
    #if ORACLE_GLINER
    true
    #else
    false
    #endif
  }

  /// Loads only explicitly installed local assets; never downloads or switches providers.
  public static func load(checkpointAt directory: URL) async throws -> Self {
    #if ORACLE_GLINER
    guard #available(macOS 14, iOS 17, *) else { throw OracleGLiNERModelError.unsupportedBuild }
    return try await Self(backend: GLiNERCoreMLBackend.load(checkpointAt: directory))
    #else
    throw OracleGLiNERModelError.unsupportedBuild
    #endif
  }
}
