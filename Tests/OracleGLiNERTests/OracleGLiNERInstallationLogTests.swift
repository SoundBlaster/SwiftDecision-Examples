import Foundation
import Testing
@testable import OracleGLiNER

struct OracleGLiNERInstallationLogTests {
  @Test func preservesOrderedEventsTimesAndFailureAcrossSerialization() throws {
    var log = OracleGLiNERInstallationLog()
    let start = Date(timeIntervalSince1970: 1_000)
    log.record(.started(version: "1.0", build: "5"), at: start)
    log.record(.stage(.download), at: start.addingTimeInterval(1))
    log.record(.progress(100), at: start.addingTimeInterval(2))
    let failure = OracleGLiNERInstallationFailure.capture(
      NSError(domain: "fixture", code: 17, userInfo: [NSLocalizedDescriptionKey: "secret-path"]),
      stage: .runtime)
    log.record(.failed(failure), at: start.addingTimeInterval(3))
    let restored = try JSONDecoder().decode(OracleGLiNERInstallationLog.self,
      from: JSONEncoder().encode(log))
    #expect(restored.entries.map(\.event) == log.entries.map(\.event))
    #expect(restored.entries.map(\.date) == log.entries.map(\.date))
    #expect(restored.entries.map(\.id) == log.entries.map(\.id))
    #expect(restored.text().contains("runtime · fixture · code 17"))
    #expect(!restored.text().contains("secret-path"))
  }

  @Test func progressDoesNotFloodJournalAndRetentionIsBounded() {
    var log = OracleGLiNERInstallationLog()
    for percent in 0 ... 100 { log.record(.progress(percent)) }
    #expect(log.entries.count == 21)
    #expect(log.entries.last?.event == .progress(100))
    log.record(.progress(-1))
    log.record(.progress(101))
    #expect(log.entries.count == 21)
    for _ in 0 ..< 400 { log.record(.stage(.files)) }
    #expect(log.entries.count == OracleGLiNERInstallationLog.maximumEntries)
    log.clear()
    #expect(log.entries.isEmpty)
  }

  @Test func fileReaderEventsPrecedeValidationFailure() async throws {
    let bytes = Data("bad".utf8)
    let inventory = try JSONSerialization.data(withJSONObject: ["files": [
      ["path": "weights", "bytes": bytes.count, "sha256": String(repeating: "0", count: 64)]
    ]])
    let files = OracleGLiNERHostedFiles(inventory: inventory)
    let events = Recorder()
    await #expect(throws: OracleGLiNERModelError.invalidFolder) {
      try await files.materialize(diagnostic: { await events.add($0) }, readFile: { _ in bytes })
    }
    #expect(await events.values == [.fileRequested(path: "weights"), .fileRead(path: "weights", bytes: 3)])
  }

  actor Recorder {
    private(set) var values: [OracleGLiNERInstallationEvent] = []
    func add(_ event: OracleGLiNERInstallationEvent) { values.append(event) }
  }
}
