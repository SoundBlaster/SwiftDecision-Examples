import CityChainGame
import SwiftUI

struct CityTurnRow: View {
  let city: USCity
  let turnNumber: Int
  let isPlayerTurn: Bool
  var isLastStop = false
  var continuation: CityLetterContinuation? = nil

  private var nextLetterLabel: String {
    if let continuation { return continuation.startingLetter.map(String.init) ?? "Any" }
    return city.lastLetter.map(String.init) ?? "Any"
  }
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(spacing: 0) {
        Text(turnNumber, format: .number)
          .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
          .foregroundStyle(isPlayerTurn ? CityChainPalette.blue : CityChainPalette.teal)
          .padding(10)
          .frame(minWidth: 38, minHeight: 38)
          .background(isPlayerTurn ? CityChainPalette.sky : CityChainPalette.mint, in: Circle())
        if !isLastStop {
          Rectangle()
            .fill(CityChainPalette.ink.opacity(0.12))
            .frame(width: 2)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 5)
        }
      }
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 6) {
        Label(
          isPlayerTurn ? "You" : "City Scout",
          systemImage: isPlayerTurn ? "person.fill" : "binoculars.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(isPlayerTurn ? CityChainPalette.blue : CityChainPalette.teal)

        Text(city.name)
          .font(.system(.title3, design: .rounded, weight: .bold))
          .foregroundStyle(CityChainPalette.ink)
          .fixedSize(horizontal: false, vertical: true)

        Text(city.state.map { "\($0.name) · \($0.abbreviation)" } ?? "United States")
          .font(.subheadline)
          .foregroundStyle(CityChainPalette.secondaryInk)
          .fixedSize(horizontal: false, vertical: true)

        if city.isStateCapital {
          CityCapitalBadge()
        }

        if let explanation = continuation?.explanation {
          Text(explanation)
            .font(.caption)
            .foregroundStyle(CityChainPalette.teal)
            .fixedSize(horizontal: false, vertical: true)
        }

        if dynamicTypeSize.isAccessibilitySize {
          Text("Next letter: \(nextLetterLabel)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(CityChainPalette.blue)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 2)
      .padding(.bottom, isLastStop ? 0 : 24)

      if !dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: 4) {
          Image(systemName: "arrow.turn.down.right")
            .font(.caption2)
          Text(nextLetterLabel)
            .font(.system(.title3, design: .rounded, weight: .heavy))
        }
        .foregroundStyle(CityChainPalette.blue)
        .padding(10)
        .background(CityChainPalette.sky.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Next letter: \(nextLetterLabel)")
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .combine)
    .accessibilityValue("Stop \(turnNumber)")
  }
}

/// Presentation stays in the app; the engine records the rule's factual result.
extension CityLetterContinuation {
  var explanation: String? {
    guard !skippedLetters.isEmpty else { return nil }
    let letters = skippedLetters.map(String.init).joined(separator: ", ")
    if let startingLetter {
      return "No unused cities for \(letters). Back through \(sourceCity.name): try \(startingLetter)."
    }
    return "We've used every option for this name's letters. Pick any new city."
  }
}
