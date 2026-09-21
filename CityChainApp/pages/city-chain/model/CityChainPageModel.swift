import CityChainGame
import Observation

@MainActor
@Observable
final class CityChainPageModel {
  private let game: CityChainGame

  private(set) var snapshot: CityGameSnapshot?
  private(set) var isSubmitting = false
  var statusMessage = "Enter the name of any US city to start."

  init(game: CityChainGame) {
    self.game = game
  }

  func load() async {
    snapshot = await game.snapshot()
  }

  func submit(_ cityName: String) async -> Bool {
    guard !isSubmitting else { return false }
    isSubmitting = true
    defer { isSubmitting = false }

    do {
      let result = try await game.submit(cityName)
      statusMessage = Self.message(for: result)
      snapshot = await game.snapshot()
      return Self.didAcceptPlayerTurn(result)
    } catch {
      statusMessage = error.localizedDescription
      snapshot = await game.snapshot()
      return false
    }
  }

  private static func didAcceptPlayerTurn(_ result: CityGameTurnResult) -> Bool {
    switch result {
    case .computerReplied, .playerWonNoAvailableReply, .playerWonBecauseComputerAbstained:
      true
    default:
      false
    }
  }

  private static func message(for result: CityGameTurnResult) -> String {
    switch result {
    case .rejected(.emptyInput):
      return "Enter a city name."
    case .rejected(.cityNameHasNoLatinLetters):
      return "Use a city name with Latin letters."
    case .rejected(.wrongStartingLetter(let expected, _)):
      return "Your city must start with \(expected)."
    case .rejected(.alreadyUsed(let city)):
      return "\(city.name) has already been used. Try another city."
    case .cityNotRecognized(let city):
      return "Noul could not verify \(city.name) as a US city."
    case .cityVerificationAbstained(let city, let reason):
      return "Noul abstained on \(city.name): \(reason)"
    case .cityVerificationFallback(let city, let reason):
      return "Noul used a fallback for \(city.name): \(reason)"
    case .computerReplied(let playerCity, let computerCity, let selection):
      let detail: String
      switch selection {
      case .onlyAvailableCity:
        detail = "It was the only legal reply."
      case .acceptedByDecision(let confidence):
        detail =
          "Choice confidence: \(confidence.formatted(.percent.precision(.fractionLength(0))))."
      case .fallbackByDecision(let confidence, let reason):
        detail =
          "Fallback selected (\(confidence.formatted(.percent.precision(.fractionLength(0))))): \(reason)"
      case .randomFallback:
        detail = "The decision backend was unavailable; a legal reply was selected at random."
      }
      return "You: \(playerCity.name) · SwiftDecision: \(computerCity.name). \(detail)"
    case .playerWonNoAvailableReply(_, let startingLetter):
      return "No unused catalog city starts with \(startingLetter). You win!"
    case .playerWonBecauseComputerAbstained(_, let reason):
      return "The computer abstained. You win! \(reason)"
    case .submissionInProgress:
      return "A turn is already being processed."
    case .gameAlreadyFinished:
      return "The game has ended."
    }
  }
}
