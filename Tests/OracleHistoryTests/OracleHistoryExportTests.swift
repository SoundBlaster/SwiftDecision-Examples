import Foundation
import OracleGame
import OracleHistory
import Testing

struct OracleHistoryExportTests {
  private struct Document: Decodable {
    let schemaVersion: Int
    let dateEncoding: String
    let exportedAt: Date
    let appVersion: String?
    let appBuild: String?
    let entries: [OracleHistoryEntry]
  }

  @Test func jsonPreservesCompleteTracePrecisionUnicodeAndEntryOrder() throws {
    let entry = makeEntry()
    let legacy = OracleHistoryEntry(question: "Older question?", answer: "Unknown", mode: "choice",
                                    confidence: nil, source: "Offline", createdAt: .distantPast)
    let export = OracleHistoryExport(entries: [entry, legacy], exportedAt: Date(timeIntervalSince1970: 42.125),
                                    appVersion: "1.2.3", appBuild: "456")
    let data = try export.jsonData()
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let decoded = try decoder.decode(Document.self, from: data)
    #expect(decoded.schemaVersion == 1)
    #expect(decoded.dateEncoding == "secondsSince1970")
    #expect(decoded.exportedAt == export.exportedAt)
    #expect(decoded.appVersion == "1.2.3")
    #expect(decoded.appBuild == "456")
    #expect(decoded.entries == [entry, legacy])
    #expect(try export.jsonData() == data)
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("0.987654321"))
    #expect(!text.contains("Authorization"))
  }

  @Test func singleQuestionExportContainsOnlyTheSelectedEntry() throws {
    let entry = makeEntry()
    let export = OracleHistoryExport(entries: [entry], exportedAt: .distantPast)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let decoded = try decoder.decode(Document.self, from: export.jsonData())
    #expect(decoded.entries.count == 1)
    #expect(decoded.entries.first?.id == entry.id)
  }

  @Test func textIncludesAllSavedEvidenceAndDoesNotRenderUserTextAsMarkup() {
    let entry = makeEntry()
    let report = OracleHistoryExport(entries: [entry], exportedAt: Date(timeIntervalSince1970: 0)).text()
    for expected in ["Oracle history export", "1970-01-01T00:00:00.000Z", "Entries: 1",
                     "  Красный или синий?\n  <b>Second line</b>",
                     "Stage ID: answer", "Raw result", "0.987654321", "0.012345679", "987654 ns",
                     "id=7, parent=3", "id=19, parent=17", "elapsed=1234567 ns"] {
      #expect(report.contains(expected), "Missing: \(expected)")
    }
    #expect(report.contains("  Selected\n"))
    #expect(report.contains("native-model@revision"))
    #expect(report.hasSuffix("\n"))
  }

  @Test func legacyAndEmptyHistoryDoNotInventTraceOrDistribution() throws {
    let legacyJSON = #"{"id":"00000000-0000-0000-0000-000000000001","question":"Q?","answer":"A","mode":"noul","source":"Offline","createdAt":0,"pipeline":[{"id":"old","title":"Legacy","decisionEvents":[],"specificationEvents":[]}]}"#
    let entry = try JSONDecoder().decode(OracleHistoryEntry.self, from: Data(legacyJSON.utf8))
    #expect(entry.pipeline?.first?.distribution == nil)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let decoded = try decoder.decode(Document.self, from: OracleHistoryExport(entries: [entry]).jsonData())
    #expect(decoded.entries == [entry])
    #expect(!OracleHistoryExport(entries: [entry]).text().contains("Full-precision distribution"))
    let noTrace = OracleHistoryEntry(question: "Q?", answer: "A", mode: "noul", confidence: nil, source: "Offline")
    #expect(OracleHistoryExport(entries: [noTrace]).text().contains("No saved pipeline."))
    let empty = OracleHistoryExport(entries: [], exportedAt: .distantPast)
    #expect(try decoder.decode(Document.self, from: empty.jsonData()).entries.isEmpty)
    #expect(empty.text().contains("Entries: 0"))
  }

  @Test @MainActor func exportDoesNotMutateHistoryOrIncludeUnrelatedPreferences() throws {
    let suite = "oracle-export-test.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("private-test-credential-not-for-export", forKey: "api-key")
    let store = OracleHistoryStore(defaults: defaults)
    store.append(question: "red or blue?", answer: .init(mode: .choice, displayText: "blue", source: .offlineFixture))
    let before = store.entries
    let snapshot = OracleHistoryExport(entries: before, exportedAt: .distantPast)
    let json = String(decoding: try snapshot.jsonData(), as: UTF8.self)
    _ = snapshot.text()
    #expect(store.entries == before)
    #expect(OracleHistoryStore(defaults: defaults).entries == before)
    #expect(!json.contains("private-test-credential-not-for-export"))
    #expect(!json.contains("api-key"))
    store.removeAll()
    #expect(snapshot.entries == before)
  }

  @Test func invalidNumbersFailInsteadOfProducingInvalidJSON() {
    let entry = OracleHistoryEntry(question: "Q?", answer: "A", mode: "noul", confidence: .nan, source: "test")
    #expect(throws: EncodingError.self) { try OracleHistoryExport(entries: [entry]).jsonData() }
  }

  private func makeEntry() -> OracleHistoryEntry {
    OracleHistoryEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
      question: "Красный или синий?\n<b>Second line</b>", answer: "синий", mode: "choice",
      confidence: 0.987654321, source: "native-model@revision", createdAt: Date(timeIntervalSince1970: 1234.125),
      pipeline: [OraclePipelineStage(id: "answer", title: "Answer decision", summary: "Raw result",
        details: [.init(id: "options", label: "Options sent", value: "Красный · синий")],
        decisionEvents: [.init(stage: "Inference completed", timestamp: Date(timeIntervalSince1970: 1235.25), detail: "native-model@revision")],
        specificationEvents: [.init(id: 7, parentID: 3, name: "acceptance policy", outcome: "Selected", durationNanoseconds: 987654)],
        orderedTrace: [.init(id: 19, parentID: 17, kind: .specification, name: "acceptance policy", detail: "Trace detail", outcome: "Selected", durationNanoseconds: 987654, elapsedNanoseconds: 1234567)],
        distribution: .init(options: ["Красный", "синий"], probabilities: [0.012345679, 0.987654321], confidence: 0.987654321))])
  }
}
