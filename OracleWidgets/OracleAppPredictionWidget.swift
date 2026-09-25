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
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Image(systemName: "sparkles")
        .font(.title2)
        .foregroundStyle(Color(red: 0.72, green: 0.53, blue: 1))

      Spacer(minLength: 0)

      Text("Ask the Oracle")
        .font(.title3.weight(.semibold))
        .foregroundStyle(.white)

      Label("Reveal in the ball", systemImage: "arrow.up.right")
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.62))
    }
    .padding(16)
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
