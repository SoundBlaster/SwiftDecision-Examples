import CityChainGame
import SwiftUI

struct GameBoardWidget: View {
  let cities: [USCity]
  var continuations: [CityLetterContinuation] = []
  var latestStopFirst = false
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      let layout =
        dynamicTypeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
      layout {
        Text("Our road trip")
          .font(.system(.title3, design: .rounded, weight: .bold))
          .foregroundStyle(CityChainPalette.ink)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(cities.count == 1 ? "1 stop" : "\(cities.count) stops")
          .font(.subheadline.weight(.semibold).monospacedDigit())
          .foregroundStyle(CityChainPalette.blue)
          .fixedSize()
      }

      if cities.isEmpty {
        EmptyRoadTripCard()
      } else {
        let turns = Array(cities.enumerated())
        let displayedTurns = latestStopFirst ? Array(turns.reversed()) : turns
        LazyVStack(spacing: 0) {
          ForEach(Array(displayedTurns.enumerated()), id: \.element.element.id) { display in
            let turn = display.element
            CityTurnRow(
              city: turn.element,
              turnNumber: turn.offset + 1,
              isPlayerTurn: turn.offset.isMultiple(of: 2),
              isLastStop: display.offset == displayedTurns.count - 1,
              continuation: continuations.first { $0.sourceCity.id == turn.element.id })
              .id(turn.element.id)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .modifier(CityChainCard())
  }
}

private struct EmptyRoadTripCard: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 10) {
        Image(systemName: "mappin.circle.fill")
          .foregroundStyle(CityChainPalette.blue)
        RouteTrail()
          .stroke(
            CityChainPalette.blue.opacity(0.25),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 6])
          )
          .frame(height: 22)
        Image(systemName: "car.side.fill")
          .foregroundStyle(CityChainPalette.teal)
          .scaleEffect(x: -1, y: 1)
        RouteTrail()
          .stroke(
            CityChainPalette.blue.opacity(0.25),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 6])
          )
          .frame(height: 22)
        Image(systemName: "flag.checkered")
          .foregroundStyle(CityChainPalette.blue)
      }
      .font(.title2)
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 5) {
        Text("Big adventures start small.")
          .font(.system(.headline, design: .rounded, weight: .bold))
          .foregroundStyle(CityChainPalette.ink)
        Text("Pick your first city above. We'll collect our stops here!")
          .font(.subheadline)
          .foregroundStyle(CityChainPalette.secondaryInk)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

private struct RouteTrail: Shape {
  func path(in rect: CGRect) -> Path {
    Path { path in
      path.move(to: CGPoint(x: rect.minX, y: rect.midY))
      path.addCurve(
        to: CGPoint(x: rect.maxX, y: rect.midY),
        control1: CGPoint(x: rect.width * 0.35, y: rect.minY),
        control2: CGPoint(x: rect.width * 0.65, y: rect.maxY))
    }
  }
}

#Preview("Collected stops") {
  ScrollView {
    GameBoardWidget(cities: [
      USCity("Austin", state: .texas, isStateCapital: true),
      USCity("Nashville", state: .tennessee, isStateCapital: true),
      USCity("Eugene", state: .oregon),
    ])
    .padding(20)
  }
  .background(CityChainPalette.paper)
}
