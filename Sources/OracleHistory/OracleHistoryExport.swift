import Foundation

/// A versioned, read-only snapshot of saved questions, answers and pipeline evidence.
///
/// Dates in JSON are Unix seconds. Exporting does not read credentials or preferences,
/// mutate history, rerun questions, or recover data that older entries did not save.
public struct OracleHistoryExport: Encodable, Sendable {
  public let schemaVersion = 1
  public let dateEncoding = "secondsSince1970"
  public let exportedAt: Date
  /// The exporting app's version, not necessarily the version that answered a question.
  public let appVersion: String?
  public let appBuild: String?
  public let entries: [OracleHistoryEntry]

  public init(
    entries: [OracleHistoryEntry],
    exportedAt: Date = .now,
    appVersion: String? = nil,
    appBuild: String? = nil
  ) {
    self.entries = entries
    self.exportedAt = exportedAt
    self.appVersion = appVersion
    self.appBuild = appBuild
  }

  /// Encodes the complete saved payload as UTF-8 JSON with stable keys and unrounded numbers.
  public func jsonData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .secondsSince1970
    return try encoder.encode(self)
  }

  /// Renders the same saved evidence as a readable UTF-8 plain-text report.
  public func text() -> String {
    let dates = ISO8601DateFormatter()
    dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var lines = ["Oracle history export", "Schema version: \(schemaVersion)",
                 "Exported at: \(dates.string(from: exportedAt))", "Entries: \(entries.count)"]
    if let appVersion { lines.append("Exporting app version: \(appVersion)") }
    if let appBuild { lines.append("Exporting app build: \(appBuild)") }

    func field(_ name: String, _ value: String, indent: String = "") {
      lines.append(indent + name + ":")
      lines += value.components(separatedBy: .newlines).map { indent + "  " + $0 }
    }
    for (index, entry) in entries.enumerated() {
      lines += ["", "=== Question \(index + 1) ===", "ID: \(entry.id.uuidString)",
                "Created at: \(dates.string(from: entry.createdAt))", "Mode: \(entry.mode)",
                "Provider: \(entry.source)"]
      field("Question", entry.question)
      field("Answer", entry.answer)
      if let confidence = entry.confidence { lines.append("Confidence: \(confidence)") }
      guard let pipeline = entry.pipeline, !pipeline.isEmpty else {
        lines.append("No saved pipeline.")
        continue
      }
      for stage in pipeline {
        lines += ["", "--- Stage: \(stage.title) ---", "Stage ID: \(stage.id)"]
        if let summary = stage.summary { field("Summary", summary) }
        for detail in stage.details ?? [] { field("\(detail.label) [\(detail.id)]", detail.value) }
        if let distribution = stage.distribution {
          lines.append("Full-precision distribution:")
          for (index, option) in distribution.options.enumerated() {
            field("Option \(index)", option, indent: "  ")
            if index < distribution.probabilities.count {
              lines.append("    Probability: \(distribution.probabilities[index])")
            }
          }
          // Retain every numeric value even if a manually constructed snapshot is malformed.
          lines.append("  Probabilities: \(distribution.probabilities)")
          lines.append("  Confidence: \(distribution.confidence)")
        }
        for event in stage.decisionEvents {
          lines.append("Decision event: \(event.stage) at \(dates.string(from: event.timestamp))")
          if let detail = event.detail { field("Detail", detail, indent: "  ") }
        }
        for event in stage.specificationEvents {
          lines.append("Specification event: id=\(event.id), parent=\(event.parentID.map(String.init) ?? "none"), duration=\(event.durationNanoseconds) ns")
          field("Rule", event.name, indent: "  ")
          field("Outcome", event.outcome, indent: "  ")
        }
        for event in stage.orderedTrace ?? [] {
          lines.append("Timeline event: id=\(event.id), parent=\(event.parentID.map(String.init) ?? "none"), kind=\(event.kind.rawValue), elapsed=\(event.elapsedNanoseconds) ns")
          field("Name", event.name, indent: "  ")
          if let outcome = event.outcome { field("Outcome", outcome, indent: "  ") }
          if let detail = event.detail { field("Detail", detail, indent: "  ") }
          if let duration = event.durationNanoseconds { lines.append("  Duration: \(duration) ns") }
        }
      }
    }
    return lines.joined(separator: "\n") + "\n"
  }
}
