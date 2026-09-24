import Foundation
import OraclePresentation
import Testing
import simd

@Test func dragMapsToBoundedRotation() {
  let target = OracleDragMotion.target(translation: [48, -24], viewportSide: 300)
  #expect(target.x > 0)
  #expect(target.y < 0)
  #expect(abs(target.x) < 0.58)
  #expect(abs(target.y) < 0.58)
}

@Test func dragRotationClampsAtItsMaximum() {
  let target = OracleDragMotion.target(translation: [2_000, -2_000], viewportSide: 300)
  #expect(abs(target.x - 0.58) < 0.0001)
  #expect(abs(target.y + 0.58) < 0.0001)
}

@Test func draggedBallMovesTowardTheFinger() {
  let target = OracleDragMotion.target(translation: [60, -30], viewportSide: 300)
  var state = OracleDragMotion.State()
  for _ in 0..<30 {
    state = OracleDragMotion.advance(state: state, target: target, deltaTime: 1.0 / 60.0)
  }
  #expect(state.rotation.x > 0)
  #expect(state.rotation.y < 0)
  #expect(abs(state.rotation.x - target.x) < 0.02)
  #expect(abs(state.rotation.y - target.y) < 0.02)
}

@Test func releasedBallSpringsBackToNeutral() {
  var state = OracleDragMotion.State(rotation: [0.5, -0.3])
  var passedNeutral = false
  for _ in 0..<180 {
    state = OracleDragMotion.advance(state: state, target: .zero, deltaTime: 1.0 / 60.0)
    if state.rotation.x < 0 { passedNeutral = true }
  }
  #expect(passedNeutral)
  #expect(simd_length(state.rotation) < 0.001)
  #expect(state == OracleDragMotion.State())
}

@Test func invalidDragInputIsSafe() {
  #expect(OracleDragMotion.target(translation: [.nan, 0], viewportSide: 300) == .zero)
  #expect(OracleDragMotion.target(translation: [1, 1], viewportSide: 0) == .zero)
  let state = OracleDragMotion.State(rotation: [0.2, -0.1])
  #expect(
    OracleDragMotion.advance(state: state, target: .zero, deltaTime: .nan)
      == OracleDragMotion.State())
}
