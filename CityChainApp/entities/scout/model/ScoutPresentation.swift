import SpecificationCore

enum ScoutMapInteractionSpec {
  /// Scout offers the map while holding it, but never over a turn still being checked.
  static func allowsMapOpening(for presentation: ScoutPresentation) -> Bool {
    PredicateSpec<ScoutPresentation>(description: "city.scout-map.available-when-holding-map-and-idle") {
      $0.pose.holdsMap && !$0.isAwaitingReply
    }
    .isSatisfiedBy(presentation)
  }
}

/// Immutable visual snapshot consumed by Scout views.
struct ScoutPresentation: Equatable {
  let pose: ScoutPose
  let reactionID: UInt64
  /// A submitted turn is still being checked; Scout's interactions stay paused.
  let isAwaitingReply: Bool

  init(pose: ScoutPose = .welcome, reactionID: UInt64 = 0, isAwaitingReply: Bool = false) {
    self.pose = pose
    self.reactionID = reactionID
    self.isAwaitingReply = isAwaitingReply
  }
}

enum ScoutPose: String, CaseIterable {
  case welcome
  case thinking
  case celebration
  case tryAnother

  var holdsMap: Bool {
    switch self {
    case .welcome, .thinking: true
    case .celebration, .tryAnother: false
    }
  }

  var assetName: String {
    switch self {
    case .welcome: "ScoutWelcome"
    case .thinking: "ScoutThinking"
    case .celebration: "ScoutCelebration"
    case .tryAnother: "ScoutTryAnother"
    }
  }
}

/// The page's single source of truth for Scout's lifecycle and visible reaction.
enum ScoutState: Equatable {
  case ready
  case preparingTurn
  case thinking
  case celebrating
  case tryAnother

  var isSubmitting: Bool {
    self == .preparingTurn || self == .thinking
  }

  var hasTurnFeedback: Bool {
    self == .celebrating || self == .tryAnother
  }

  var pose: ScoutPose {
    switch self {
    case .ready, .preparingTurn: .welcome
    case .thinking: .thinking
    case .celebrating: .celebration
    case .tryAnother: .tryAnother
    }
  }

  fileprivate func next(for event: ScoutEvent) -> ScoutState? {
    switch (self, event) {
    case (.ready, .submit), (.celebrating, .submit), (.tryAnother, .submit):
      .preparingTurn
    case (.preparingTurn, .thinkingDelayElapsed):
      .thinking
    case (.preparingTurn, .turnAccepted), (.thinking, .turnAccepted):
      .celebrating
    case (.preparingTurn, .turnRejected), (.thinking, .turnRejected):
      .tryAnother
    case (.celebrating, .feedbackDismissed), (.tryAnother, .feedbackDismissed):
      .ready
    case (_, .newRoundStarted):
      .ready
    default:
      nil
    }
  }
}

enum ScoutEvent {
  case submit
  case thinkingDelayElapsed
  case turnAccepted
  case turnRejected
  case feedbackDismissed
  case newRoundStarted
}

struct ScoutStateMachine {
  private(set) var state: ScoutState = .ready
  private var reactionID: UInt64 = 0

  var isSubmitting: Bool { state.isSubmitting }
  var hasTurnFeedback: Bool { state.hasTurnFeedback }
  var isIdle: Bool { state == .ready }
  var presentation: ScoutPresentation {
    ScoutPresentation(pose: state.pose, reactionID: reactionID, isAwaitingReply: state.isSubmitting)
  }

  @discardableResult
  mutating func send(_ event: ScoutEvent) -> Bool {
    guard let nextState = state.next(for: event), nextState != state else { return false }

    let poseChanged = state.pose != nextState.pose
    state = nextState
    if poseChanged {
      reactionID &+= 1
    }
    return true
  }
}
