import CityChainGame
import SwiftUI

struct GameBoardWidget: View {
  let cities: [USCity]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Label("Our road trip", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
          .font(.title3.weight(.bold))
          .foregroundStyle(CityChainPalette.ink)
        Spacer()
        Text("\(cities.count) \(cities.count == 1 ? "stop" : "stops")")
          .font(.subheadline.weight(.semibold).monospacedDigit())
          .foregroundStyle(CityChainPalette.blue)
          .accessibilityLabel("\(cities.count) cities visited")
      }

      if cities.isEmpty {
        EmptyRoadTripCard()
      } else {
        LazyVStack(spacing: 0) {
          ForEach(Array(cities.enumerated()), id: \.element.id) { turn in
            CityTurnRow(
              city: turn.element,
              turnNumber: turn.offset + 1,
              isPlayerTurn: turn.offset.isMultiple(of: 2))

            if turn.offset < cities.count - 1 {
              Rectangle()
                .fill(CityChainPalette.blue.opacity(0.13))
                .frame(height: 1)
                .padding(.leading, 58)
            }
          }
        }
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .shadow(color: CityChainPalette.ink.opacity(0.08), radius: 18, y: 8)
  }
}

private struct EmptyRoadTripCard: View {
  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: "car.side.fill")
        .font(.system(size: 27, weight: .semibold))
        .foregroundStyle(CityChainPalette.blue)
        .frame(width: 48, height: 48)
        .background(CityChainPalette.sky, in: RoundedRectangle(cornerRadius: 15))
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text("Your trip starts here")
          .font(.headline.weight(.bold))
          .foregroundStyle(CityChainPalette.ink)
        Text("Name a city, then follow its last letter.")
          .font(.subheadline)
          .foregroundStyle(CityChainPalette.ink.opacity(0.68))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 6)
  }
}
