import CryptoKit
import Foundation
import Testing
@testable import OracleGLiNER

struct OracleGLiNERDistributionTests {
  @Test func validatesHashesAndRejectsTamperingAndUnexpectedFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let bytes = Data("original".utf8)
    let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    let encoded = try JSONSerialization.data(withJSONObject: ["files": [["path": "weights", "bytes": bytes.count, "sha256": hash]]])
    let manifest = try JSONDecoder().decode(OracleGLiNERDistribution.self, from: encoded)
    let weights = root.appendingPathComponent("weights")
    try bytes.write(to: weights)
    try manifest.validate(directory: root)
    try Data("modified".utf8).write(to: weights)
    #expect(throws: OracleGLiNERModelError.invalidFolder) { try manifest.validate(directory: root) }
    try bytes.write(to: weights)
    try Data().write(to: root.appendingPathComponent("unexpected"))
    #expect(throws: OracleGLiNERModelError.invalidFolder) { try manifest.validate(directory: root) }
  }

  @Test func rejectedHostedCandidateDoesNotReplaceExistingModel() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("candidate")
    try FileManager.default.createDirectory(at: source.appendingPathComponent("GLiNERSmall.mlpackage"), withIntermediateDirectories: true)
    for name in ["gliner.json", "tokenizer.json", "tokenizer_config.json"] {
      try Data("invalid".utf8).write(to: source.appendingPathComponent(name))
    }
    let active = root.appendingPathComponent("active")
    try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: active.appendingPathComponent("sentinel"))
    let store = OracleGLiNERModelStore(directory: active, loader: { _ in
      Issue.record("invalid distribution must be rejected before Core ML")
      throw OracleGLiNERModelError.invalidFolder
    })
    await #expect(throws: (any Error).self) { try await store.importDistribution(from: source) }
    #expect(try Data(contentsOf: active.appendingPathComponent("sentinel")) == Data("keep".utf8))
  }
}
