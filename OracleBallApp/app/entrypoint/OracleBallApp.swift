import RealityKit
import SwiftUI

@main
struct OracleBallApp: App {
  init() {
    OracleRevealComponent.registerComponent()
    OracleRevealSystem.registerSystem()
  }

  var body: some SwiftUI.Scene {
    WindowGroup { OraclePage().preferredColorScheme(.dark) }
  }
}
