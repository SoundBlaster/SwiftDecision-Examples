import Foundation
import OracleGame
import OracleHistory
import Testing

struct OracleFailedHistoryTests {
  @Test @MainActor func failureAfterClearIsPersistedAndExportableWithoutAnAnswer() throws {
    let name = "oracle-failed-history.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = OracleHistoryStore(defaults: defaults)
    store.append(question: "Old?", answer: .init(mode: .choice, displayText: "Old", source: .offlineFixture))
    store.removeAll()
    let failure = OracleTracedFailure(kind: "timeout", mode: .choice, provider: "local-model",
      pipeline: [.init(id: "failed", title: "Answer decision", summary: "Request failed")])
    store.appendFailure(question: "День или ночь", failure: failure, message: "The model timed out.")
    let reloaded = OracleHistoryStore(defaults: defaults)
    let entry = try #require(reloaded.entries.first)
    #expect(reloaded.entries.count == 1)
    #expect(entry.question == "День или ночь")
    #expect(entry.answer.isEmpty && entry.confidence == nil)
    #expect(entry.failure?.kind == "timeout")
    #expect(entry.pipeline == failure.pipeline)
    let json = String(decoding: try OracleHistoryExport(entries: reloaded.entries).jsonData(), as: UTF8.self)
    #expect(json.contains("\"failure\"") && json.contains("\"timeout\""))
    #expect(OracleHistoryExport(entries: reloaded.entries).text().contains("Outcome: failed"))
    #expect(!json.contains("\"distribution\""))
  }
}
