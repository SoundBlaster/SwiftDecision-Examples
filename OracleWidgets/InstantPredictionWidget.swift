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

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("INSTANT PREDICTION", systemImage: "sparkles")
        .font(.caption.weight(.semibold))
        .tracking(1.1)
        .foregroundStyle(.white.opacity(0.65))

      Spacer(minLength: 0)

      Text(entry.answer ?? "Ask the oracle")
        .font(.title2.weight(.semibold))
        .foregroundStyle(.white)
        .lineLimit(3)
        .minimumScaleFactor(0.75)
        .accessibilityAddTraits(.updatesFrequently)

      Button(intent: GenerateInstantPredictionIntent()) {
        Label(entry.answer == nil ? "Reveal" : "Ask again", systemImage: "arrow.clockwise")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white)
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.white.opacity(0.12), in: Capsule())
    }
    .padding(16)
    .containerBackground(for: .widget) {
      LinearGradient(
        colors: [Color(red: 0.09, green: 0.06, blue: 0.28), Color(red: 0.015, green: 0.02, blue: 0.09)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)
    }
  }
}
