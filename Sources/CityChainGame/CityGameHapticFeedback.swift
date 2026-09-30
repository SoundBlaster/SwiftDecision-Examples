import SpecificationCore

/// A meaningful game transition that the app can translate into a platform haptic.
public enum CityGameHapticEvent: Sendable, Equatable {
  case scoutThinking
  case scoutReplied
  case turnRejected
  case hintUnlocked
  case roundWon
  case newRoundStarted
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
