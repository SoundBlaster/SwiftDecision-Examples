import Foundation

/// Coordinates app-owned delivery with store-owned validation/atomic activation.
@MainActor
public struct OracleGLiNERInstaller {
  public enum Update: Equatable, Sendable {
    case downloading(Double?)
    case validating
  }
  private let source: any OracleGLiNERDownloadSource
  private let diagnostic: OracleGLiNERDiagnosticSink
  private let activate: @Sendable (URL) async throws -> Void

  public init(source: any OracleGLiNERDownloadSource, store: OracleGLiNERModelStore,
              diagnostic: @escaping OracleGLiNERDiagnosticSink = { _ in }) {
    self.source = source
    self.diagnostic = diagnostic
    self.activate = { try await store.importDistribution(from: $0) }
  }

  init(source: any OracleGLiNERDownloadSource, activate: @escaping @Sendable (URL) async throws -> Void) {
    self.source = source
    self.activate = activate
    self.diagnostic = { _ in }
  }

  public func install(update: @escaping @MainActor @Sendable (Update) -> Void) async throws {
    let directory = try await source.download { update(.downloading($0)) }
    try Task.checkCancellation()
    update(.validating)
    do {
      try await activate(directory)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw OracleGLiNERInstallationFailure.capture(error, stage: .validation)
    }
    try Task.checkCancellation()
    // The store owns its validated copy. Cache cleanup cannot invalidate that activation.
    await diagnostic(.stage(.cacheCleanup))
    do {
      try await source.releaseDownloadedFiles()
      await diagnostic(.cacheReleased)
    } catch {
      await diagnostic(.cacheReleaseFailed(.capture(error, stage: .cacheCleanup)))
    }
  }
}
