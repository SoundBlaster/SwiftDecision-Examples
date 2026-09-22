import RealityKit
import SwiftUI

@main
struct OracleBallApp: App {
  init() {
    OracleRevealComponent.registerComponent()
    OracleMotionComponent.registerComponent()
    OracleFieldComponent.registerComponent()
    OracleRevealSystem.registerSystem()
    OracleFieldSystem.registerSystem()
  }

  var body: some SwiftUI.Scene {
    WindowGroup { OraclePage().preferredColorScheme(.dark) }
  }
}
