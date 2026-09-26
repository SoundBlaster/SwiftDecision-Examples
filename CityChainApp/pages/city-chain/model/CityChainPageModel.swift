import CityChainGame
import Observation

@MainActor
@Observable
final class CityChainPageModel {
  private let game: CityChainGame

  private(set) var snapshot: CityGameSnapshot?
  private(set) var isSubmitting = false
  var cityInput = ""
  var statusMessage = String(localized: "Pick a city from the U.S. atlas to start your trip.")

  init(game: CityChainGame) {
    self.game = game
  }

  func load() async {
    snapshot = await game.snapshot()
  }

  func startNewRound() async {
    guard !isSubmitting else { return }
    await game.reset()
    cityInput = ""
    statusMessage = String(localized: "Pick a city from the U.S. atlas to start your trip.")
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
      statusMessage = String(localized: "I can't check that city right now. Try a suggested city!")
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
      return String(localized: "Type a city name to play.")
    case .rejected(.cityNameHasNoLatinLetters):
      return String(localized: "Use English letters in city names.")
    case .rejected(.wrongStartingLetter(let expected, _)):
      return Self.format("Find a city that starts with %@!", String(expected))
    case .rejected(.alreadyUsed(let city)):
      return Self.format("We already visited %@. Pick another!", city.name)
    case .cityNotRecognized(let city):
      return Self.format("I couldn't find %@ in my atlas yet. Try a suggested city!", city.name)
    case .cityVerificationAbstained(let city, _):
      return Self.format("I'm not sure about %@ yet. Try a suggested city!", city.name)
    case .cityVerificationFallback(let city, _):
      return Self.format("Let's try a city from the atlas instead of %@.", city.name)
    case .computerReplied(let playerCity, let computerCity, let selection):
      switch selection {
      case .onlyAvailableCity:
        return Self.format("Great job with %@! My only city was %@.", playerCity.name, computerCity.name)
      case .acceptedByDecision:
        return Self.format("Great job with %@! I choose %@.", playerCity.name, computerCity.name)
      case .fallbackByDecision:
        return Self.format("Great job with %@! I choose %@.", playerCity.name, computerCity.name)
      case .randomFallback:
        return Self.format("Great job with %@! I picked %@ from my atlas.", playerCity.name, computerCity.name)
      }
    case .playerWonNoAvailableReply(_, let startingLetter):
      return Self.format("No more cities start with %@. You win this round!", String(startingLetter))
    case .playerWonBecauseComputerAbstained:
      return String(localized: "I can't think of a city. You win this round!")
    case .submissionInProgress:
      return String(localized: "One moment, I'm thinking!")
    case .gameAlreadyFinished:
      return String(localized: "This round is over. Start a new trip!")
    }
  }

  private static func format(_ key: String, _ arguments: CVarArg...) -> String {
    String(
      format: String(localized: String.LocalizationValue(key)),
      locale: Locale(identifier: "en_US"),
      arguments: arguments)
  }
}
