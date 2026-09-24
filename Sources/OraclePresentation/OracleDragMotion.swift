import Foundation
import simd

/// Maps a one-finger drag to a bounded ball rotation and springs it back to rest.
public enum OracleDragMotion {
  public struct State: Equatable, Sendable {
    public var rotation: SIMD2<Float>
    public var velocity: SIMD2<Float>

    public init(rotation: SIMD2<Float> = .zero, velocity: SIMD2<Float> = .zero) {
      self.rotation = rotation
      self.velocity = velocity
    }
  }

  private static let maximumAngle: Float = 0.58
  private static let stiffness: Float = 180
  private static let damping: Float = 18

  /// Horizontal drag rotates around the vertical axis; vertical drag follows the finger.
  public static func target(translation: SIMD2<Float>, viewportSide: Float) -> SIMD2<Float> {
    guard translation.x.isFinite, translation.y.isFinite,
      viewportSide.isFinite, viewportSide > 0
    else {
      return .zero
    }

    let travel = max(viewportSide * 0.32, 1)
    return SIMD2(
      clamped(translation.x / travel) * maximumAngle,
      clamped(translation.y / travel) * maximumAngle)
  }

  /// Advances a damped spring using a bounded time step for stable frame-rate-independent motion.
  public static func advance(
    state: State,
    target: SIMD2<Float>,
    deltaTime: TimeInterval
  ) -> State {
    guard deltaTime.isFinite,
      state.rotation.x.isFinite, state.rotation.y.isFinite,
      state.velocity.x.isFinite, state.velocity.y.isFinite,
      target.x.isFinite, target.y.isFinite
    else {
      return State()
    }

    let dt = Float(max(0, min(deltaTime, 0.05)))
    guard dt > 0 else { return state }

    let acceleration = (target - state.rotation) * stiffness - state.velocity * damping
    let velocity = state.velocity + acceleration * dt
    let rotation = state.rotation + velocity * dt
    if simd_length(rotation) < 0.0005, simd_length(velocity) < 0.005, target == .zero {
      return State()
    }
    return State(rotation: rotation, velocity: velocity)
  }

  private static func clamped(_ value: Float) -> Float {
    min(max(value, -1), 1)
  }
}
