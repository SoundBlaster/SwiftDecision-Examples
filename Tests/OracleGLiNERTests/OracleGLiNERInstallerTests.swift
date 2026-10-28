import Foundation
import Testing
@testable import OracleGLiNER

@MainActor
struct OracleGLiNERInstallerTests {
  @MainActor final class Source: OracleGLiNERDownloadSource {
    var fails = false
    var cancelTask = false
    var released = false
    func download(progress: @escaping @MainActor @Sendable (Double?) -> Void) async throws -> URL {
      progress(0.5)
      if fails { throw URLError(.notConnectedToInternet) }
      if cancelTask { withUnsafeCurrentTask { $0?.cancel() } }
      return URL(fileURLWithPath: "/model")
    }
    func cancel() {}
    func releaseDownloadedFiles() async throws { released = true }
  }
  actor Activation {
    var calls = 0
    func run(_ url: URL) { calls += 1 }
  }

  @Test func deliveryActivatesBeforeReleasingCache() async throws {
    let source = Source()
    let activation = Activation()
    let installer = OracleGLiNERInstaller(source: source) { await activation.run($0) }
    try await installer.install { _ in }
    #expect(await activation.calls == 1)
    #expect(source.released)
  }

  @Test func deliveryFailureAndCancellationNeverActivate() async {
    for cancellation in [false, true] {
      let source = Source()
      source.fails = !cancellation
      source.cancelTask = cancellation
      let activation = Activation()
      let task = Task {
        let installer = OracleGLiNERInstaller(source: source) { await activation.run($0) }
        try await installer.install { _ in }
      }
      await #expect(throws: (any Error).self) { try await task.value }
      #expect(await activation.calls == 0)
      #expect(!source.released)
    }
  }

  @Test func validationFailureKeepsDownloadedFilesForDiagnosis() async {
    let source = Source()
    let installer = OracleGLiNERInstaller(source: source) { _ in throw OracleGLiNERModelError.invalidFolder }
    do {
      try await installer.install { _ in }
      Issue.record("Expected a validation failure")
    } catch let failure as OracleGLiNERInstallationFailure {
      #expect(failure.stage == .validation)
    } catch {
      Issue.record("Expected safe installation diagnostics")
    }
    #expect(!source.released)
  }
}
