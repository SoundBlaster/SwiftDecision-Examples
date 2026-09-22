import Foundation
import simd

/// Pure presentation math; independent of RealityKit, inference, and wall-clock time.
public enum TriangleReveal {
  public struct Frame: Sendable {
    public let position: SIMD3<Float>
    public let orientation: simd_quatf
    public let fogDistance: Float
    public let clarity: Float
  }

  public static func sample(elapsed: TimeInterval, reduceMotion: Bool) -> Frame {
    let time = Float(max(0, elapsed))
    let progress = smoothstep(time / (reduceMotion ? 0.25 : 1.4))
    let movement: Float = reduceMotion ? 1 : progress
    let z: Float = 0.05 + 0.68 * movement
    let bob: Float = reduceMotion ? 0 : 0.0108 * sin(time * 1.7) * progress
    let initial =
      simd_quatf(angle: -0.85, axis: [1, 0, 0])
      * simd_quatf(angle: 0.25, axis: [0, 1, 0])
    let rotation = simd_slerp(initial, simd_quatf(angle: 0, axis: [0, 1, 0]), movement)
    let roll: Float = reduceMotion ? 0 : 0.027 * sin(time * 1.3) * progress
    let pitch: Float = reduceMotion ? 0 : 0.026 * sin(time * 1.05) * progress
    let yaw: Float = reduceMotion ? 0 : 0.02 * sin(time * 0.85) * progress
    return Frame(
      position: [0, -0.10 * (1 - movement) + bob, z],
      orientation: simd_quatf(angle: roll, axis: [0, 0, 1])
        * simd_quatf(angle: pitch, axis: [1, 0, 0])
        * simd_quatf(angle: yaw, axis: [0, 1, 0]) * rotation,
      fogDistance: 0.854 - (0.05 + 0.68 * progress),
      clarity: smoothstep((progress - 0.25) / 0.75)
    )
  }

  private static func smoothstep(_ value: Float) -> Float {
    let x = min(max(value, 0), 1)
    return x * x * (3 - 2 * x)
  }
}
