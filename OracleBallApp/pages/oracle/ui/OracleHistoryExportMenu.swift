import CoreTransferable
import OracleHistory
import SwiftUI
import UniformTypeIdentifiers

/// Shares an immutable history snapshot; serialization happens only when requested.
struct OracleHistoryExportMenu: View {
  let entries: [OracleHistoryEntry]
  var isSingleQuestion = false

  private var title: LocalizedStringKey { isSingleQuestion ? "Export question" : "Export history" }
  private var fileName: String {
    isSingleQuestion ? "oracle-question-\(entries.first?.id.uuidString ?? "export")" : "oracle-history"
  }

  var body: some View {
    Menu {
      ShareLink(item: OracleJSONExport(entries: entries, fileName: fileName), preview: SharePreview(title)) {
        Label("Export JSON", systemImage: "curlybraces")
      }
      .accessibilityIdentifier("oracle.export.json")
      ShareLink(item: OracleTextExport(entries: entries, fileName: fileName), preview: SharePreview(title)) {
        Label("Export text", systemImage: "doc.text")
      }
      .accessibilityIdentifier("oracle.export.text")
    } label: {
      Label(title, systemImage: "square.and.arrow.up")
    }
    .disabled(entries.isEmpty)
    .accessibilityIdentifier(isSingleQuestion ? "oracle.pipeline.export" : "oracle.history.export")
  }
}

private struct OracleJSONExport: Transferable, Sendable {
  let entries: [OracleHistoryEntry]
  let fileName: String

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .json) { item in
      try makeSnapshot(entries: item.entries).jsonData()
    }
    .suggestedFileName { $0.fileName + ".json" }
  }
}

private struct OracleTextExport: Transferable, Sendable {
  let entries: [OracleHistoryEntry]
  let fileName: String

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .utf8PlainText) { item in
      Data(makeSnapshot(entries: item.entries).text().utf8)
    }
    .suggestedFileName { $0.fileName + ".txt" }
  }
}

private func makeSnapshot(entries: [OracleHistoryEntry]) -> OracleHistoryExport {
  OracleHistoryExport(entries: entries,
    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
    appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
}
