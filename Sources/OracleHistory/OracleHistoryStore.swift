import Foundation
import OracleGame

/// A locally stored question and its display-ready oracle answer.
public struct OracleHistoryEntry: Codable, Hashable, Identifiable, Sendable {
  public let id: UUID
  public let question: String
  public let answer: String
  public let mode: String
  public let confidence: Double?
  public let source: String
  public let createdAt: Date
  /// The content-free SwiftDecision and SpecificationCore stages for this answer.
  public let pipeline: [OraclePipelineStage]?

  public init(
    id: UUID = UUID(),
    question: String,
    answer: String,
    mode: String,
    confidence: Double?,
    source: String,
    createdAt: Date = .now,
    pipeline: [OraclePipelineStage]? = nil
  ) {
    self.id = id
    self.question = question
    self.answer = answer
    self.mode = mode
    self.confidence = confidence
    self.source = source
    self.createdAt = createdAt
    self.pipeline = pipeline
  }

  public init(
    question: String,
    answer: OracleAnswer,
    createdAt: Date = .now,
    pipeline: [OraclePipelineStage]? = nil
  ) {
    self.init(
      question: question,
      answer: answer.displayText,
      mode: answer.mode.rawValue,
      confidence: answer.confidence,
      source: Self.sourceLabel(answer.source),
      createdAt: createdAt,
      pipeline: pipeline)
  }

  private static func sourceLabel(_ source: OracleAnswerSource) -> String {
    switch source {
    case .offlineFixture:
      "Offline"
    case let .simulated(identifier):
      identifier
    case let .model(identifier):
      identifier
    }
  }
}

/// Persists a bounded, newest-first history in UserDefaults without encryption.
@MainActor
public final class OracleHistoryStore {
  public static let defaultLimit = 50

  public private(set) var entries: [OracleHistoryEntry]

  private let defaults: UserDefaults
  private let storageKey: String
  private let limit: Int

  public init(
    defaults: UserDefaults = .standard,
    storageKey: String = "com.soundblaster.oracleball.question-history",
    limit: Int = OracleHistoryStore.defaultLimit
  ) {
    self.defaults = defaults
    self.storageKey = storageKey
    self.limit = max(1, limit)
    if let data = defaults.data(forKey: storageKey),
       let entries = try? JSONDecoder().decode([OracleHistoryEntry].self, from: data)
    {
      self.entries = Array(entries.prefix(max(1, limit)))
    } else {
      entries = []
    }
  }

  @discardableResult
  public func append(
    question: String,
    answer: OracleAnswer,
    createdAt: Date = .now,
    pipeline: [OraclePipelineStage]? = nil
  ) -> OracleHistoryEntry {
    let entry = OracleHistoryEntry(
      question: question,
      answer: answer,
      createdAt: createdAt,
      pipeline: pipeline)
    entries.insert(entry, at: 0)
    entries = Array(entries.prefix(limit))
    persist()
    return entry
  }

  public func remove(id: OracleHistoryEntry.ID) {
    entries.removeAll { $0.id == id }
    persist()
  }

  public func removeAll() {
    entries.removeAll()
    defaults.removeObject(forKey: storageKey)
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(entries) else { return }
    defaults.set(data, forKey: storageKey)
  }
}
