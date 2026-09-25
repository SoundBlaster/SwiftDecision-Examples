import RealityKit

struct OracleFieldComponent: Component {
  let pulses: [Entity]
  var windowReflection: ModelEntity?
  var elapsed: Double = 0
  var reduceMotion: Bool
  var isPaused: Bool
}
