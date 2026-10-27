import RealityKit
import SwiftUI
#if DEBUG
import OracleGLiNER
#endif

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
    #if DEBUG
      .backgroundTask(.urlSession(OracleGLiNERBackgroundTransfer.identifier)) {
        await OracleGLiNERBackgroundTransfer.shared.handleBackgroundEvents()
      }
    #endif
  }
}
