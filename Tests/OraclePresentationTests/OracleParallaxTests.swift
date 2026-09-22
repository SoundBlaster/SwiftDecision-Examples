import Foundation
import OraclePresentation
import simd
import Testing

@Test func equalAttitudesProduceZeroTilt() {
  let neutral = simd_quatf(angle: 0.7, axis: SIMD3<Float>(1, 2, 3))
  #expect(OracleParallax.target(attitude: neutral, neutral: neutral) == .zero)
}

@Test func relativeRotationMapsToScreenLocalAxes() {
  let neutral = simd_quatf(angle: 0.4, axis: SIMD3<Float>(0, 1, 0))
  let attitude = neutral * simd_quatf(angle: 0.2, axis: SIMD3<Float>(0, 1, 0))
  let tilt = OracleParallax.target(attitude: attitude, neutral: neutral)
  #expect(abs(tilt.x - 0.2) < 0.0001)
  #expect(abs(tilt.y) < 0.0001)
}

@Test func targetIsBounded() {
  let attitude = simd_quatf(angle: 2, axis: SIMD3<Float>(1, 1, 0))
  let tilt = OracleParallax.target(attitude: attitude, neutral: simd_quatf(angle: 0, axis: [0, 1, 0]))
  #expect(abs(tilt.x) <= 0.35)
  #expect(abs(tilt.y) <= 0.35)
}

@Test func antipodalQuaternionsProduceTheSameTarget() {
  let q = simd_quatf(angle: 0.25, axis: SIMD3<Float>(1, 2, 3))
  let antipodal = simd_quatf(vector: -q.vector)
  let neutral = simd_quatf(angle: 0, axis: [0, 1, 0])
  #expect(OracleParallax.target(attitude: q, neutral: neutral)
    == OracleParallax.target(attitude: antipodal, neutral: neutral))
}

@Test func smoothingMovesMonotonicallyAndIsTimeStepIndependent() {
  let target = SIMD2<Float>(0.3, -0.2)
  var first = SIMD2<Float>.zero
  for _ in 0..<10 { first = OracleParallax.smooth(current: first, target: target, deltaTime: 0.01) }
  var second = SIMD2<Float>.zero
  for _ in 0..<2 { second = OracleParallax.smooth(current: second, target: target, deltaTime: 0.05) }
  #expect(first.x > 0 && first.x < target.x)
  #expect(first.y < 0 && first.y > target.y)
  #expect(abs(first.x - second.x) < 0.001)
  #expect(abs(first.y - second.y) < 0.001)
}

@Test func invalidSamplesAreSafe() {
  let zero = simd_quatf(vector: .zero)
  let invalid = simd_quatf(vector: SIMD4<Float>(.nan, 0, 0, 1))
  #expect(OracleParallax.target(attitude: zero, neutral: zero) == .zero)
  #expect(OracleParallax.target(attitude: invalid, neutral: zero) == .zero)
  let current = SIMD2<Float>(0.1, -0.2)
  #expect(OracleParallax.smooth(current: current, target: .zero, deltaTime: .nan) == current)
}
