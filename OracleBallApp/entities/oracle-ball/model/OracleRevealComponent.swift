import RealityKit

struct OracleRevealComponent: Component {
  enum Phase { case submerging, stirring, revealing, holding }
  var phase: Phase = .revealing
  var elapsed: Double = 0
  var retreatFrom: Double = 1.4
  var answerReady = false
  var reduceMotion = false
  var isPaused = false
}
