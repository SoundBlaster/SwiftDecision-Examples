import SpecificationCore

/// A semantic haptic outcome selected for a game transition or interface interaction.
public enum CityGameHapticEvent: Sendable, Equatable {
  case scoutThinking
  case scoutReplied
  case turnRejected
  case hintUnlocked
  case roundWon
  case newRoundStarted
  case toolbarButtonPressed
  case suggestedCitySelected
  case hintRevealed
  case hintsPopoverDismissed
  case mapTapped
  case mapCitySelected
  case scoutQuoteDismissed
  case mapClosed
}

/// Interface events whose haptic behavior is selected by `CityGameHapticInteractionSpec`.
public enum CityGameHapticInteraction: Sendable, Equatable {
  case toolbarButtonPressed
  case suggestedCitySelected
  case hintRevealed
  case hintsPopoverVisibilityChanged(
    wasPresented: Bool, isPresented: Bool, programmaticDismissal: Bool)
  case mapTapped
  case mapCitySelected
  case scoutQuoteDismissed
  case mapClosed
}

public enum CityGameHapticPhase: Sendable, Equatable {
  case playerCityCommitted
  case turnCompleted
  case roundStarted
}

public struct CityGameHapticContext: Sendable {
  public let phase: CityGameHapticPhase
  public let previousSnapshot: CityGameSnapshot?
  public let currentSnapshot: CityGameSnapshot
  public let result: CityGameTurnResult?
  public let failedUnexpectedly: Bool

  public init(
    phase: CityGameHapticPhase,
    previousSnapshot: CityGameSnapshot?,
    currentSnapshot: CityGameSnapshot,
    result: CityGameTurnResult? = nil,
    failedUnexpectedly: Bool = false
  ) {
    self.phase = phase
    self.previousSnapshot = previousSnapshot
    self.currentSnapshot = currentSnapshot
    self.result = result
    self.failedUnexpectedly = failedUnexpectedly
  }
}

/// Selects at most one haptic for a state transition, with round completion taking priority.
public struct CityGameHapticFeedbackSpec: DecisionSpec {
  public typealias Context = CityGameHapticContext
  public typealias Result = CityGameHapticEvent

  private let routing = Self.makeRouting()

  public init() {}

  public func decide(_ context: Context) -> Result? {
    routing.decide(context)
  }

  private static func makeRouting() -> FirstMatchSpec<Context, Result> {
    FirstMatchSpec([
      (PredicateSpec<Context>(description: "city.haptic.round-started", matchesRoundStart), .newRoundStarted),
      (PredicateSpec<Context>(description: "city.haptic.round-won", matchesRoundWin), .roundWon),
      (PredicateSpec<Context>(description: "city.haptic.scout-replied", matchesScoutReply), .scoutReplied),
      (PredicateSpec<Context>(description: "city.haptic.hint-unlocked", unlocksHint), .hintUnlocked),
      (PredicateSpec<Context>(description: "city.haptic.turn-rejected", rejectsTurn), .turnRejected),
      (PredicateSpec<Context>(description: "city.haptic.scout-thinking", startsScoutThinking), .scoutThinking),
    ])
  }

  private static func matchesRoundStart(_ context: Context) -> Bool {
    context.phase == .roundStarted
  }

  private static func matchesRoundWin(_ context: Context) -> Bool {
    guard context.phase == .turnCompleted, let result = context.result else { return false }
    return isRoundWin(result)
  }

  private static func matchesScoutReply(_ context: Context) -> Bool {
    guard context.phase == .turnCompleted, let result = context.result else { return false }
    return isScoutReply(result)
  }

  private static func unlocksHint(_ context: Context) -> Bool {
    context.phase == .turnCompleted
      && context.previousSnapshot?.cityHint == nil
      && context.currentSnapshot.cityHint != nil
  }

  private static func rejectsTurn(_ context: Context) -> Bool {
    guard context.phase == .turnCompleted else { return false }
    guard let result = context.result else { return context.failedUnexpectedly }
    return isRejected(result)
  }

  private static func startsScoutThinking(_ context: Context) -> Bool {
    guard context.phase == .playerCityCommitted,
          let previousSnapshot = context.previousSnapshot
    else { return false }
    let cityCountIncreased = context.currentSnapshot.usedCities.count > previousSnapshot.usedCities.count
    return context.currentSnapshot.isSubmissionInProgress && cityCountIncreased
  }

  private static func isRoundWin(_ result: CityGameTurnResult) -> Bool {
    switch result {
    case .playerWonNoAvailableReply, .playerWonBecauseComputerAbstained: true
    default: false
    }
  }

  private static func isScoutReply(_ result: CityGameTurnResult) -> Bool {
    if case .computerReplied = result { return true }
    return false
  }

  private static func isRejected(_ result: CityGameTurnResult) -> Bool {
    switch result {
    case .rejected, .cityNotRecognized, .cityVerificationAbstained, .cityVerificationFallback:
      true
    default:
      false
    }
  }
}

/// Routes explicit interface interactions to haptics through SpecificationCore.
public struct CityGameHapticInteractionSpec: DecisionSpec {
  public typealias Context = CityGameHapticInteraction
  public typealias Result = CityGameHapticEvent

  private let routing = Self.makeRouting()

  public init() {}

  public func decide(_ context: Context) -> Result? {
    routing.decide(context)
  }

  private static func makeRouting() -> FirstMatchSpec<Context, Result> {
    FirstMatchSpec([
      (
        PredicateSpec<Context>(
          description: "city.haptic.hints-popover-dismissed", hintsPopoverWasDismissed),
        .hintsPopoverDismissed),
      (
        PredicateSpec<Context>(description: "city.haptic.toolbar-button", {
          $0 == .toolbarButtonPressed
        }), .toolbarButtonPressed),
      (
        PredicateSpec<Context>(description: "city.haptic.suggested-city-selected", {
          $0 == .suggestedCitySelected
        }), .suggestedCitySelected),
      (
        PredicateSpec<Context>(description: "city.haptic.hint-revealed", {
          $0 == .hintRevealed
        }), .hintRevealed),
      (
        PredicateSpec<Context>(description: "city.haptic.map-tapped", { $0 == .mapTapped }),
        .mapTapped),
      (
        PredicateSpec<Context>(description: "city.haptic.map-city-selected", {
          $0 == .mapCitySelected
        }), .mapCitySelected),
      (
        PredicateSpec<Context>(description: "city.haptic.scout-quote-dismissed", {
          $0 == .scoutQuoteDismissed
        }), .scoutQuoteDismissed),
      (
        PredicateSpec<Context>(description: "city.haptic.map-closed", { $0 == .mapClosed }),
        .mapClosed),
    ])
  }

  private static func hintsPopoverWasDismissed(_ interaction: Context) -> Bool {
    guard
      case let .hintsPopoverVisibilityChanged(wasPresented, isPresented, programmaticDismissal) =
        interaction
    else {
      return false
    }
    return wasPresented && !isPresented && !programmaticDismissal
  }
}
