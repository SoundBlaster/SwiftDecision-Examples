import SwiftUI
import WidgetKit

struct InstantPredictionWidget: Widget {
  static let kind = "com.soundblaster.oracleball.instant-prediction"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: Self.kind, provider: OracleWidgetTimelineProvider()) { entry in
      InstantPredictionWidgetView(entry: entry)
    }
    .configurationDisplayName("Instant prediction")
    .description("Reveal a random prediction right on your Home Screen.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

private struct InstantPredictionWidgetView: View {
  let entry: OracleWidgetEntry
  @Environment(\.widgetFamily) private var family

  private var isSmall: Bool { family == .systemSmall }

  @ViewBuilder
  private var header: some View {
    if isSmall {
      HStack(alignment: .top, spacing: 6) {
        Image(systemName: "sparkles")
        Text("INSTANT PREDICTION")
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      .font(.caption2.weight(.semibold))
      .tracking(0.5)
      .foregroundStyle(.white.opacity(0.65))
    } else {
      Label("INSTANT PREDICTION", systemImage: "sparkles")
        .font(.caption.weight(.semibold))
        .tracking(1.1)
        .foregroundStyle(.white.opacity(0.65))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: isSmall ? 8 : 10) {
      header

      Spacer(minLength: 0)

      Text(entry.answer ?? "Ask the oracle")
        .font((isSmall ? Font.headline : Font.title2).weight(.semibold))
        .foregroundStyle(.white)
        .lineLimit(isSmall ? 2 : 3)
        .minimumScaleFactor(0.65)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.updatesFrequently)

      Button(intent: GenerateInstantPredictionIntent()) {
        Label(entry.answer == nil ? "Reveal" : "Ask again", systemImage: "arrow.clockwise")
          .font((isSmall ? Font.caption : Font.subheadline).weight(.semibold))
          .foregroundStyle(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      .buttonStyle(.plain)
      .padding(.horizontal, isSmall ? 10 : 12)
      .padding(.vertical, isSmall ? 6 : 8)
      .background(.white.opacity(0.12), in: Capsule())
    }
    .padding(isSmall ? 12 : 16)
    .containerBackground(for: .widget) {
      LinearGradient(
        colors: [Color(red: 0.09, green: 0.06, blue: 0.28), Color(red: 0.015, green: 0.02, blue: 0.09)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)
    }
  }
}
