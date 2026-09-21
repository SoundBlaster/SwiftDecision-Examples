import CityChainGame
import SwiftUI

struct CityTurnRow: View {
  let city: USCity
  let turnNumber: Int
  let speaker: String

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text("\(turnNumber)")
        .font(.caption.monospacedDigit())
        .foregroundStyle(.tertiary)
        .frame(minWidth: 28, alignment: .leading)

      VStack(alignment: .leading) {
        Text(city.name)
          .font(.body.weight(.medium))
        Text(speaker)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Text(city.lastLetter.map(String.init) ?? "—")
        .font(.caption.weight(.semibold).monospaced())
        .foregroundStyle(.tint)
        .accessibilityLabel("Next letter: \(city.lastLetter.map(String.init) ?? "unknown")")
    }
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }
}
