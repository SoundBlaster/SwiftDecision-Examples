/// Visual state only. The page model maps game outcomes to Scout's reactions.
struct ScoutPresentation: Equatable {
  private(set) var pose: ScoutPose = .welcome
  private(set) var reactionID: UInt64 = 0

  mutating func present(_ pose: ScoutPose) {
    self.pose = pose
    // Repeated outcomes still deserve feedback, including two errors in a row.
    reactionID &+= 1
  }
}

enum ScoutPose: String, CaseIterable {
  case welcome
  case thinking
  case celebration
  case tryAnother

  var assetName: String {
    switch self {
    case .welcome: "ScoutWelcome"
    case .thinking: "ScoutThinking"
    case .celebration: "ScoutCelebration"
    case .tryAnother: "ScoutTryAnother"
    }
  }
}
