import CityChainGame
import SwiftUI

struct GameBoardWidget: View {
  let cities: [USCity]
  var continuations: [CityLetterContinuation] = []
  var latestStopFirst = false
  @State private var routeLayout: RoadTripLayout = .list
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
        HStack(spacing: 8) {
          Text(cities.count == 1 ? "1 stop" : "\(cities.count) stops")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(CityChainPalette.blue)
            .fixedSize()

          if !cities.isEmpty {
            Button {
              routeLayout = routeLayout == .list ? .horizontal : .list
            } label: {
              Image(systemName: routeLayout == .list ? "rectangle.stack" : "list.bullet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CityChainPalette.blue)
                .frame(width: 36, height: 36)
                .background(CityChainPalette.sky.opacity(0.72), in: Circle())
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
              routeLayout == .list ? "Show route as horizontal cards" : "Show route as a vertical list")
            .accessibilityHint("Changes how the stops in your road trip are displayed")
          }
        }
      }

      if cities.isEmpty {
        EmptyRoadTripCard()
      } else {
        let turns = Array(cities.enumerated())
        let displayedTurns = latestStopFirst ? Array(turns.reversed()) : turns
        if routeLayout == .list {
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
        } else {
          ScrollViewReader { proxy in
            ScrollView(.horizontal) {
              LazyHStack(alignment: .top, spacing: 12) {
                ForEach(Array(displayedTurns.enumerated()), id: \.element.element.id) { display in
                  let turn = display.element
                  HStack(spacing: 12) {
                    if display.offset > 0 {
                      Image(systemName: latestStopFirst ? "arrow.left" : "arrow.right")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(CityChainPalette.blue)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    }

                    CityRouteStopCard(
                      city: turn.element,
                      turnNumber: turn.offset + 1,
                      isPlayerTurn: turn.offset.isMultiple(of: 2),
                      continuation: continuations.first { $0.sourceCity.id == turn.element.id })
                      .id(turn.element.id)
                  }
                }
              }
              .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .onChange(of: cities.last?.id, initial: true) { _, latestCityID in
              guard latestStopFirst, let latestCityID else { return }
              var transaction = Transaction()
              transaction.disablesAnimations = true
              withTransaction(transaction) {
                proxy.scrollTo(latestCityID, anchor: .leading)
              }
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .modifier(CityChainCard())
  }
}

private enum RoadTripLayout {
  case list
  case horizontal
}

private struct CityRouteStopCard: View {
  let city: USCity
  let turnNumber: Int
  let isPlayerTurn: Bool
  let continuation: CityLetterContinuation?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var nextLetter: String {
    if let continuation { return continuation.startingLetter.map(String.init) ?? "Any" }
    return city.lastLetter.map(String.init) ?? "Any"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Text(turnNumber, format: .number)
          .font(.subheadline.weight(.bold).monospacedDigit())
          .foregroundStyle(isPlayerTurn ? CityChainPalette.blue : CityChainPalette.teal)
          .frame(width: 32, height: 32)
          .background(isPlayerTurn ? CityChainPalette.sky : CityChainPalette.mint, in: Circle())
          .accessibilityHidden(true)

        Label(
          isPlayerTurn ? "You" : "City Scout",
          systemImage: isPlayerTurn ? "person.fill" : "binoculars.fill")
          .font(.caption.weight(.semibold))
          .foregroundStyle(isPlayerTurn ? CityChainPalette.blue : CityChainPalette.teal)
          .lineLimit(1)

        Spacer(minLength: 0)
      }

      Text(city.name)
        .font(.system(.title3, design: .rounded, weight: .bold))
        .foregroundStyle(CityChainPalette.ink)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)

      Text(city.state.map { "\($0.name) · \($0.abbreviation)" } ?? "United States")
        .font(.subheadline)
        .foregroundStyle(CityChainPalette.secondaryInk)
        .lineLimit(2)

      if city.isStateCapital {
        CityCapitalBadge()
      }

      if dynamicTypeSize.isAccessibilitySize {
        Text("Next letter: \(nextLetter)")
          .font(.caption.weight(.semibold))
          .foregroundStyle(CityChainPalette.blue)
      } else {
        Label("\(nextLetter)", systemImage: "arrow.turn.down.right")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(CityChainPalette.blue)
          .padding(.horizontal, 10)
          .padding(.vertical, 7)
          .background(CityChainPalette.sky.opacity(0.72), in: Capsule())
      }
    }
    .frame(width: 220)
    .frame(minHeight: 196, alignment: .topLeading)
    .padding(16)
    .background(.white, in: RoundedRectangle(cornerRadius: 20))
    .overlay {
      RoundedRectangle(cornerRadius: 20)
        .strokeBorder(CityChainPalette.ink.opacity(0.08), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityValue("Stop \(turnNumber)")
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
