import Foundation

/// Coordinates app-owned delivery with store-owned validation/atomic activation.
@MainActor
public struct OracleGLiNERInstaller {
  public enum Update: Equatable, Sendable {
    case downloading(Double?)
    case validating
  }
  private let source: any OracleGLiNERDownloadSource
  private let activate: @Sendable (URL) async throws -> Void

  public init(source: any OracleGLiNERDownloadSource, store: OracleGLiNERModelStore) {
    self.source = source
    self.activate = { try await store.importDistribution(from: $0) }
  }

  init(source: any OracleGLiNERDownloadSource, activate: @escaping @Sendable (URL) async throws -> Void) {
    self.source = source
    self.activate = activate
  }

  public func install(update: @escaping @MainActor @Sendable (Update) -> Void) async throws {
    let directory = try await source.download { update(.downloading($0)) }
    try Task.checkCancellation()
    update(.validating)
    try await activate(directory)
    try Task.checkCancellation()
    // The store owns its validated copy. Cache cleanup cannot invalidate that activation.
    try? await source.releaseDownloadedFiles()
  }
}
