#if DEBUG && canImport(ZIPFoundation)
import CryptoKit
import Foundation
import Testing
import ZIPFoundation
@testable import OracleGLiNER

struct OracleGLiNERReleaseArchiveTests {
  private func fixture(contents: Data = Data("model".utf8), expected: Data = Data("model".utf8),
                       path: String = "model.bin") throws -> (URL, Data, String) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let url = root.appendingPathComponent("model.zip")
    let archive = try Archive(url: url, accessMode: .create)
    try archive.addEntry(with: "GLiNERSmall/" + path, type: .file, uncompressedSize: Int64(contents.count)) { position, size in
      contents.subdata(in: Int(position) ..< Int(position) + size)
    }
    let inventory = try JSONSerialization.data(withJSONObject: ["files": [[
      "path": "model.bin", "bytes": expected.count, "sha256": hash(expected)
    ]]])
    return (url, inventory, hash(try Data(contentsOf: url)))
  }

  private func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  @Test func extractsOnlyAfterBothArchiveAndFileHashesMatch() async throws {
    let (url, inventory, digest) = try fixture()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let extracted = try await OracleGLiNERReleaseArchive.extract(at: url,
      expectedBytes: Data(contentsOf: url).count, expectedSHA256: digest, inventory: inventory)
    defer { try? FileManager.default.removeItem(at: extracted) }
    #expect(try Data(contentsOf: extracted.appendingPathComponent("model.bin")) == Data("model".utf8))
    #expect(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("distribution.json").path))
  }

  @Test func rejectsChangedArchiveBeforeExtraction() async throws {
    let (url, inventory, _) = try fixture()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    await #expect(throws: OracleGLiNERModelError.self) {
      try await OracleGLiNERReleaseArchive.extract(at: url,
        expectedBytes: Data(contentsOf: url).count, expectedSHA256: "wrong", inventory: inventory)
    }
  }

  @Test func rejectsFilesThatDoNotMatchPinnedInventory() async throws {
    let (url, inventory, digest) = try fixture(contents: Data("wrong".utf8))
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    await #expect(throws: OracleGLiNERModelError.self) {
      try await OracleGLiNERReleaseArchive.extract(at: url,
        expectedBytes: Data(contentsOf: url).count, expectedSHA256: digest, inventory: inventory)
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["ORACLE_GITHUB_DOWNLOAD_SMOKE"] == "1",
                 "Explicit ~70 MB GitHub download; never runs in ordinary CI."))
  @MainActor func explicitLiveGitHubDownload() async throws {
    let source = OracleGLiNERGitHubSource()
    var progress: [Double] = []
    let directory = try await source.download { if let value = $0 { progress.append(value) } }
    #expect(progress.contains { $0 > 0 && $0 < 1 })
    #expect(progress.last == 1)
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("gliner.json").path))
    try await source.releaseDownloadedFiles()
    #expect(!FileManager.default.fileExists(atPath: directory.path))
  }
}
#endif
