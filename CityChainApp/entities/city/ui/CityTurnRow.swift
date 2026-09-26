import CityChainGame
import SwiftUI

struct CityTurnRow: View {
  let city: USCity
  let turnNumber: Int
  let isPlayerTurn: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ZStack(alignment: .bottomTrailing) {
        Image(systemName: isPlayerTurn ? "person.fill" : "sparkles")
          .font(.system(size: 19, weight: .bold))
          .foregroundStyle(isPlayerTurn ? CityChainPalette.blue : CityChainPalette.lavender)
          .frame(width: 42, height: 42)
          .background(
            isPlayerTurn ? CityChainPalette.sky.opacity(0.72) : CityChainPalette.lavender.opacity(0.14),
            in: Circle())

        Text("\(turnNumber)")
          .font(.caption2.weight(.heavy).monospacedDigit())
          .foregroundStyle(.white)
          .frame(width: 18, height: 18)
          .background(CityChainPalette.orange, in: Circle())
          .overlay(Circle().stroke(.white, lineWidth: 2))
          .offset(x: 3, y: 3)
          .accessibilityHidden(true)
      }
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(city.name)
            .font(.title3.weight(.bold))
            .foregroundStyle(CityChainPalette.ink)
            .fixedSize(horizontal: false, vertical: true)

          if city.isStateCapital {
            Text("CAPITAL")
              .font(.caption2.weight(.heavy))
              .tracking(0.5)
              .foregroundStyle(CityChainPalette.lavender)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(CityChainPalette.lavender.opacity(0.12), in: Capsule())
              .accessibilityLabel("State capital")
          }
        }

        HStack(spacing: 6) {
          Text(city.state.map { "\($0.name) · \($0.abbreviation)" } ?? "United States")
            .font(.subheadline)
            .foregroundStyle(CityChainPalette.ink.opacity(0.68))

          Text("·")
            .foregroundStyle(CityChainPalette.ink.opacity(0.42))
            .accessibilityHidden(true)

          Text(isPlayerTurn ? "You" : "City Scout")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isPlayerTurn ? CityChainPalette.blue : CityChainPalette.lavender)
        }
        .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 4)

      if let lastLetter = city.lastLetter {
        Text(String(lastLetter))
          .font(.system(.title3, design: .rounded, weight: .black))
          .foregroundStyle(.white)
          .frame(width: 36, height: 36)
          .background(CityChainPalette.blue, in: Circle())
          .accessibilityLabel("Ends with \(lastLetter)")
      }
    }
    .padding(.vertical, 13)
    .accessibilityElement(children: .combine)
  }
}
