import CityChainGame
import SwiftUI

struct GameBoardWidget: View {
  let cities: [USCity]

  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        Text("Game board")
          .font(.headline)
        Spacer()
        Text(String(format: String(localized: "Cities · %lld"), Int64(cities.count)))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if cities.isEmpty {
        ContentUnavailableView(
          "The chain starts here",
          systemImage: "point.topleft.down.curvedto.point.bottomright.up",
          description: Text("Your first city can be any city in the United States.")
        )
        .frame(minHeight: 180)
      } else {
        LazyVStack {
          ForEach(Array(cities.enumerated()), id: \.element.id) { turn in
            CityTurnRow(
              city: turn.element,
              turnNumber: turn.offset + 1,
              speaker: turn.offset.isMultiple(of: 2) ? "You" : "SwiftDecision"
            )
          }
        }
      }
    }
    .padding()
    .background(.background, in: RoundedRectangle(cornerRadius: 20))
  }
}
