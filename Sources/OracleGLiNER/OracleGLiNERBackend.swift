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

  /// A local dummy inference prepares Core ML execution before accepting a real question.
  /// This is not an Oracle decision and is never written to question history.
  func warmUp() async throws {
    try Task.checkCancellation()
    _ = try await backend.predict(for: DecisionPrompt(id: "oracle.gliner.warm-up", kind: .choice,
      instructions: "Choose a color.", context: "Blue is a color.",
      options: [.init(id: "0", description: "red"), .init(id: "1", description: "blue")]))
    try Task.checkCancellation()
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
    let result = try await Self(backend: GLiNERCoreMLBackend.load(checkpointAt: directory,
                                                               choiceOrdering: .canonical))
    try await result.warmUp()
    return result
    #else
    throw OracleGLiNERModelError.unsupportedBuild
    #endif
  }
}
