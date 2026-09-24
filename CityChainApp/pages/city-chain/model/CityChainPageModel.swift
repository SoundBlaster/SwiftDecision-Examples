import CityChainGame
import Observation

@MainActor
@Observable
final class CityChainPageModel {
  private let game: CityChainGame

  private(set) var snapshot: CityGameSnapshot?
  private(set) var isSubmitting = false
  var statusMessage = String(localized: "Enter the name of any US city to start.")

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
      return String(localized: "Enter a city name.")
    case .rejected(.cityNameHasNoLatinLetters):
      return String(localized: "Use a city name with Latin letters.")
    case .rejected(.wrongStartingLetter(let expected, _)):
      return Self.format("Your city must start with %@.", String(expected))
    case .rejected(.alreadyUsed(let city)):
      return Self.format("%@ has already been used. Try another city.", city.name)
    case .cityNotRecognized(let city):
      return Self.format("Noul could not verify %@ as a US city.", city.name)
    case .cityVerificationAbstained(let city, let reason):
      return Self.format("Noul abstained on %@: %@", city.name, reason)
    case .cityVerificationFallback(let city, let reason):
      return Self.format("Noul used a fallback for %@: %@", city.name, reason)
    case .computerReplied(let playerCity, let computerCity, let selection):
      let detail: String
      switch selection {
      case .onlyAvailableCity:
        detail = String(localized: "It was the only legal reply.")
      case .acceptedByDecision(let confidence):
        detail = Self.format(
          "Choice confidence: %@.", confidence.formatted(.percent.precision(.fractionLength(0))))
      case .fallbackByDecision(let confidence, let reason):
        detail = Self.format(
          "Fallback selected (%@): %@",
          confidence.formatted(.percent.precision(.fractionLength(0))), reason)
      case .randomFallback:
        detail = String(localized: "The decision backend was unavailable; a legal reply was selected at random.")
      }
      return Self.format("You: %@ · SwiftDecision: %@. %@", playerCity.name, computerCity.name, detail)
    case .playerWonNoAvailableReply(_, let startingLetter):
      return Self.format("No unused catalog city starts with %@. You win!", String(startingLetter))
    case .playerWonBecauseComputerAbstained(_, let reason):
      return Self.format("The computer abstained. You win! %@", reason)
    case .submissionInProgress:
      return String(localized: "A turn is already being processed.")
    case .gameAlreadyFinished:
      return String(localized: "The game has ended.")
    }
  }

  private static func format(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: String(localized: String.LocalizationValue(key)), locale: .current, arguments: arguments)
  }
}
