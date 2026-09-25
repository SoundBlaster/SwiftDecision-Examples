import Foundation
import WidgetKit

struct OracleWidgetEntry: TimelineEntry {
  let date: Date
  let answer: String?
  let updatedAt: Date?
}

struct OracleWidgetTimelineProvider: TimelineProvider {
  func placeholder(in context: Context) -> OracleWidgetEntry {
    OracleWidgetEntry(date: .now, answer: "A favorable turn", updatedAt: .now)
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
    return OracleWidgetEntry(
      date: .now,
      answer: defaults?.string(forKey: OracleWidgetSharedState.answerKey),
      updatedAt: defaults?.object(forKey: OracleWidgetSharedState.updatedAtKey) as? Date)
  }
}
