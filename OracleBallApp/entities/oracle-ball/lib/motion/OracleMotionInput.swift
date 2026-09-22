import CoreMotion
import OraclePresentation
import UIKit
import simd

/// The render loop reads the latest fused gyroscope sample; no sensor-driven SwiftUI updates.
@MainActor
final class OracleMotionInput {
  private let manager = CMMotionManager()
  private var neutral: simd_quatf?
  private var orientation = UIDeviceOrientation.portrait

  func setActive(_ active: Bool) {
    guard active, manager.isDeviceMotionAvailable else {
      manager.stopDeviceMotionUpdates()
      neutral = nil
      return
    }
    guard !manager.isDeviceMotionActive else { return }
    neutral = nil
    manager.deviceMotionUpdateInterval = 1.0 / 60.0
    manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
  }

  func sample() -> SIMD2<Float> {
    guard let motion = manager.deviceMotion else { return .zero }
    let currentOrientation = UIDevice.current.orientation
    if currentOrientation.isPortrait || currentOrientation.isLandscape,
       currentOrientation != orientation {
      orientation = currentOrientation
      neutral = nil
    }
    let q = motion.attitude.quaternion
    let attitude = simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
    guard let neutral else {
      self.neutral = attitude
      return .zero
    }
    let tilt = OracleParallax.target(attitude: attitude, neutral: neutral)
    switch orientation {
    case .landscapeLeft: return [-tilt.y, tilt.x]
    case .landscapeRight: return [tilt.y, -tilt.x]
    case .portraitUpsideDown: return -tilt
    default: return tilt
    }
  }

  isolated deinit { manager.stopDeviceMotionUpdates() }
}
