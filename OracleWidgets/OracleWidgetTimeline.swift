import Foundation
import OracleHistory
import WidgetKit

struct OracleWidgetEntry: TimelineEntry {
  let date: Date
  let answer: String?
  let updatedAt: Date?
  let isWelcomeCompleted: Bool
}

struct OracleWidgetTimelineProvider: TimelineProvider {
  func placeholder(in context: Context) -> OracleWidgetEntry {
    OracleWidgetEntry(date: .now, answer: nil, updatedAt: nil, isWelcomeCompleted: false)
  }

  func getSnapshot(in context: Context, completion: @escaping (OracleWidgetEntry) -> Void) {
    completion(currentEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<OracleWidgetEntry>) -> Void) {
    let entry = currentEntry()
    completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(12 * 60 * 60))))
  }

  private func currentEntry() -> OracleWidgetEntry {
    let defaults = OracleWidgetSharedState.defaults
    let isWelcomeCompleted = OracleWidgetAccess.isAllowed(in: defaults)
    return OracleWidgetEntry(
      date: .now,
      answer: isWelcomeCompleted ? defaults?.string(forKey: OracleWidgetSharedState.answerKey) : nil,
      updatedAt: isWelcomeCompleted ? defaults?.object(forKey: OracleWidgetSharedState.updatedAtKey) as? Date : nil,
      isWelcomeCompleted: isWelcomeCompleted)
  }
}
