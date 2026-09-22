import Foundation
import simd

/// Converts device attitude changes into a bounded, screen-local tilt target.
public enum OracleParallax {
  private static let limit: Float = 0.35
  private static let damping: Float = 0.18

  public static func target(attitude: simd_quatf, neutral: simd_quatf) -> SIMD2<Float> {
    guard let attitude = normalized(attitude), let neutral = normalized(neutral) else {
      return .zero
    }

    let relative = neutral.inverse * attitude
    let normal = relative.act(SIMD3<Float>(0, 0, 1))
    guard normal.x.isFinite, normal.y.isFinite, normal.z.isFinite else { return .zero }

    return SIMD2(
      clamped(atan2(normal.x, normal.z)),
      clamped(atan2(normal.y, normal.z))
    )
  }

  public static func smooth(
    current: SIMD2<Float>, target: SIMD2<Float>, deltaTime: TimeInterval
  ) -> SIMD2<Float> {
    guard deltaTime.isFinite else { return current }
    guard current.x.isFinite, current.y.isFinite else { return .zero }
    guard target.x.isFinite, target.y.isFinite else { return current }

    let dt = Float(max(0, min(deltaTime, 0.1)))
    let alpha = 1 - exp(-dt / damping)
    return current + (target - current) * alpha
  }

  private static func normalized(_ quaternion: simd_quatf) -> simd_quatf? {
    let vector = quaternion.vector
    guard vector.x.isFinite, vector.y.isFinite, vector.z.isFinite, vector.w.isFinite else {
      return nil
    }
    let magnitude = simd_length(vector)
    guard magnitude.isFinite, magnitude > .ulpOfOne else { return nil }
    return simd_quatf(vector: vector / magnitude)
  }

  private static func clamped(_ value: Float) -> Float {
    min(max(value, -limit), limit)
  }
}
