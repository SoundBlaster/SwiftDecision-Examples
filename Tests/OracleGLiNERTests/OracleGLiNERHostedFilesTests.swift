import CryptoKit
import Foundation
import Testing
@testable import OracleGLiNER

struct OracleGLiNERHostedFilesTests {
  private func inventory(for bytes: Data) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["files": [
      ["path": "Model/weights", "bytes": bytes.count,
       "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()]
    ]])
  }

  @Test func materializesLogicalFilesWithoutDirectoryAccess() async throws {
    let bytes = Data("model".utf8)
    let files = OracleGLiNERHostedFiles(inventory: try inventory(for: bytes))
    let root = try await files.materialize { path in
      #expect(path == "Model/weights")
      return bytes
    }
    #expect(try Data(contentsOf: root.appendingPathComponent("Model/weights")) == bytes)
    #expect(try root.appendingPathComponent("Model/weights")
      .resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false)
    try await files.removeTemporaryFiles()
    #expect(!FileManager.default.fileExists(atPath: root.path))
  }

  @Test func cachedFilesAreReadAgainAndTamperingStillFails() async throws {
    let bytes = Data("model".utf8)
    let files = OracleGLiNERHostedFiles(inventory: try inventory(for: bytes))
    let root = try await files.materialize { _ in bytes }
    await #expect(throws: OracleGLiNERModelError.invalidFolder) {
      try await files.materialize { _ in Data("other".utf8) }
    }
    #expect(!FileManager.default.fileExists(atPath: root.path))
    // A later retry with valid cached bytes succeeds without a new network download.
    let retry = try await files.materialize { _ in bytes }
    #expect(FileManager.default.fileExists(atPath: retry.path))
    try await files.removeTemporaryFiles()
  }

  @Test func diagnosticRetainsStageAndCodeWithoutRawErrorMetadata() {
    let original = NSError(domain: "fixture", code: 7,
      userInfo: [NSLocalizedDescriptionKey: "private-path-and-token"])
    let failure = OracleGLiNERInstallationFailure.capture(original, stage: .files)
    #expect(failure.stage == .files)
    #expect(failure.domain == "fixture")
    #expect(failure.code == 7)
    #expect(!String(describing: failure).contains("private-path-and-token"))
    #expect(OracleGLiNERInstallationFailure.capture(failure, stage: .validation) == failure)
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["ORACLE_GLINER_CHECKPOINT"] != nil,
                 "Opt-in installed model smoke; no network access."))
  func pinnedHostedFilesActivateWithTheNativeRuntime() async throws {
    let source = URL(fileURLWithPath: try #require(
      ProcessInfo.processInfo.environment["ORACLE_GLINER_CHECKPOINT"]))
    let files = try OracleGLiNERHostedFiles()
    let materialized = try await files.materialize { path in
      try Data(contentsOf: source.appendingPathComponent(path), options: .mappedIfSafe)
    }
    let active = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = OracleGLiNERModelStore(directory: active)
    do {
      try await store.importDistribution(from: materialized)
      #expect(await store.isInstalled)
      try await store.removeModel()
      try await files.removeTemporaryFiles()
    } catch {
      try? await store.removeModel()
      try? await files.removeTemporaryFiles()
      throw error
    }
  }

}
