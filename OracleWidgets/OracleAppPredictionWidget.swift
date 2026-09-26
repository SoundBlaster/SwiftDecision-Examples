import SwiftUI
import WidgetKit

struct OracleAppPredictionWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "com.soundblaster.oracleball.open-app", provider: OracleWidgetTimelineProvider()) { _ in
      OracleAppPredictionWidgetView()
    }
    .configurationDisplayName("Ask the Oracle")
    .description("Open the Oracle and reveal a prediction in the magic ball.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

private struct OracleAppPredictionWidgetView: View {
  @Environment(\.widgetFamily) private var family

  private var isSmall: Bool { family == .systemSmall }

  var body: some View {
    VStack(alignment: .leading, spacing: isSmall ? 8 : 12) {
      Image(systemName: "sparkles")
        .font(isSmall ? .title3 : .title2)
        .foregroundStyle(Color(red: 0.72, green: 0.53, blue: 1))

      Spacer(minLength: isSmall ? 4 : 0)

      Text("Ask the Oracle")
        .font((isSmall ? Font.headline : Font.title3).weight(.semibold))
        .foregroundStyle(.white)
        .lineLimit(2)
        .minimumScaleFactor(0.75)
        .fixedSize(horizontal: false, vertical: true)

      Label("Reveal in the ball", systemImage: "arrow.up.right")
        .font((isSmall ? Font.caption2 : Font.caption).weight(.medium))
        .foregroundStyle(.white.opacity(0.62))
        .lineLimit(2)
        .minimumScaleFactor(0.75)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .containerBackground(for: .widget) {
      LinearGradient(
        colors: [Color(red: 0.09, green: 0.06, blue: 0.28), Color(red: 0.015, green: 0.02, blue: 0.09)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)
    }
    .widgetURL(URL(string: "oracleball://random"))
  }
}
