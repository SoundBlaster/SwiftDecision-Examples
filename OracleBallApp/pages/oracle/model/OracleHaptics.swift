import CoreHaptics

enum OracleHapticCue {
  case submit
  case clear
  case positiveResult
  case negativeResult

  var events: [CHHapticEvent] {
    switch self {
    case .submit:
      // Rising intensity and sharpness suggest three ascending notes without audio.
      return [
        Self.tap(at: 0, intensity: 0.28, sharpness: 0.35),
        Self.tap(at: 0.11, intensity: 0.48, sharpness: 0.55),
        Self.tap(at: 0.22, intensity: 0.72, sharpness: 0.78),
      ]
    case .clear:
      return [Self.tap(at: 0, intensity: 0.5, sharpness: 0.45)]
    case .positiveResult:
      return [
        Self.tap(at: 0, intensity: 0.38, sharpness: 0.65),
        Self.longTap(at: 0.15),
      ]
    case .negativeResult:
      return [
        Self.longTap(at: 0),
        Self.tap(at: 0.29, intensity: 0.38, sharpness: 0.65),
      ]
    }
  }

  private static func tap(at time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
    CHHapticEvent(
      eventType: .hapticTransient,
      parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
      ],
      relativeTime: time)
  }

  private static func longTap(at time: TimeInterval) -> CHHapticEvent {
    CHHapticEvent(
      eventType: .hapticContinuous,
      parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.85),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.55),
      ],
      relativeTime: time,
      duration: 0.19)
  }
}

@MainActor
protocol OracleHapticFeedback {
  func play(_ cue: OracleHapticCue)
  func startShakeFeedback()
  func stopShakeFeedback()
}

@MainActor
final class OracleHaptics: OracleHapticFeedback {
  private static let submissionCueDuration: TimeInterval = 0.25

  private let engine: CHHapticEngine?
  private var submissionCueEndTime: TimeInterval = 0
  private var deferredResultTask: Task<Void, Never>?
  private var shakePlayer: CHHapticPatternPlayer?

  init() {
    guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
      engine = nil
      return
    }
    engine = try? CHHapticEngine()
  }

  func play(_ cue: OracleHapticCue) {
    let now = ProcessInfo.processInfo.systemUptime
    switch cue {
    case .submit:
      deferredResultTask?.cancel()
      deferredResultTask = nil
      submissionCueEndTime = now + Self.submissionCueDuration
      playImmediately(cue)
    case .clear:
      playImmediately(cue)
    case .positiveResult, .negativeResult:
      let delay = submissionCueEndTime - now
      guard delay > 0 else {
        playImmediately(cue)
        return
      }

      deferredResultTask?.cancel()
      deferredResultTask = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        guard let self, !Task.isCancelled else { return }
        self.deferredResultTask = nil
        self.playImmediately(cue)
      }
    }
  }

  func startShakeFeedback() {
    guard shakePlayer == nil, let engine else { return }
    let event = CHHapticEvent(
      eventType: .hapticContinuous,
      parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.18),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.22),
      ],
      relativeTime: 0,
      duration: 30)
    do {
      let pattern = try CHHapticPattern(events: [event], parameters: [])
      try engine.start()
      let player = try engine.makePlayer(with: pattern)
      try player.start(atTime: CHHapticTimeImmediate)
      shakePlayer = player
    } catch {
      // Haptic availability must not affect the question or its answer.
    }
  }

  func stopShakeFeedback() {
    guard let shakePlayer else { return }
    try? shakePlayer.stop(atTime: CHHapticTimeImmediate)
    self.shakePlayer = nil
  }

  private func playImmediately(_ cue: OracleHapticCue) {
    guard let engine else { return }
    do {
      let pattern = try CHHapticPattern(events: cue.events, parameters: [])
      try engine.start()
      let player = try engine.makePlayer(with: pattern)
      try player.start(atTime: CHHapticTimeImmediate)
    } catch {
      // Haptic availability must not affect the question or its answer.
    }
  }
}
