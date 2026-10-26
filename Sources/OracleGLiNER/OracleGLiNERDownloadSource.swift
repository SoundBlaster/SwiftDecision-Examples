import Foundation

/// The app owns delivery; model validation/activation stays independent of the host.
@MainActor
public protocol OracleGLiNERDownloadSource {
  func download(progress: @escaping @MainActor @Sendable (Double?) -> Void) async throws -> URL
  func cancel()
  func releaseDownloadedFiles() async throws
}
