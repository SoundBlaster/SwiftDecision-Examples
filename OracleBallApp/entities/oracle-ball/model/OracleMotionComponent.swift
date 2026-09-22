import RealityKit

struct OracleMotionComponent: Component {
  let input: OracleMotionInput
  let ball: Entity
  let camera: PerspectiveCamera
  let lighting: Entity
  let contour: Entity
  var tilt: SIMD2<Float> = .zero
  var elapsed: Double = 0
  var reduceMotion = false
  var isPaused = false
}
