import CoreMotion
import Foundation
import OraclePresentation
import UIKit
import simd

/// The render loop reads the latest fused gyroscope sample; no sensor-driven SwiftUI updates.
@MainActor
final class OracleMotionInput {
  private let manager = CMMotionManager()
  private var neutral: simd_quatf?
  private var orientation = UIDeviceOrientation.portrait
  private var onShake: (() -> Void)?
  private var onShakeActivityChanged: ((Bool) -> Void)?
  private var isShakeEnabled = true
  private var isShakeArmed = true
  private var isShakeActive = false
  private var quietSince: TimeInterval?

  func setShakeHandler(_ handler: @escaping () -> Void) {
    onShake = handler
  }

  func setShakeActivityHandler(_ handler: @escaping (Bool) -> Void) {
    onShakeActivityChanged = handler
  }

  func setShakeEnabled(_ enabled: Bool) {
    isShakeEnabled = enabled
    if !enabled {
      setShakeActive(false)
    }
  }

  func setActive(_ active: Bool) {
    guard active, manager.isDeviceMotionAvailable else {
      manager.stopDeviceMotionUpdates()
      neutral = nil
      setShakeActive(false)
      return
    }
    guard !manager.isDeviceMotionActive else { return }
    neutral = nil
    manager.deviceMotionUpdateInterval = 1.0 / 60.0
    manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
  }

  func sample() -> SIMD2<Float> {
    guard let motion = manager.deviceMotion else { return .zero }
    detectShake(using: motion)
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

  private func detectShake(using motion: CMDeviceMotion) {
    guard isShakeEnabled else {
      quietSince = nil
      setShakeActive(false)
      return
    }
    let acceleration = motion.userAcceleration
    let magnitude = sqrt(
      acceleration.x * acceleration.x
        + acceleration.y * acceleration.y
        + acceleration.z * acceleration.z)
    let now = ProcessInfo.processInfo.systemUptime

    if magnitude < 0.6 {
      guard !isShakeArmed else { return }
      if let quietSince {
        if now - quietSince >= 0.5 {
          isShakeArmed = true
          self.quietSince = nil
          setShakeActive(false)
        }
      } else {
        quietSince = now
      }
      return
    }

    quietSince = nil
    guard magnitude >= 2.0, isShakeArmed else { return }
    isShakeArmed = false
    setShakeActive(true)
    onShake?()
  }

  private func setShakeActive(_ active: Bool) {
    guard isShakeActive != active else { return }
    isShakeActive = active
    onShakeActivityChanged?(active)
  }

  isolated deinit { manager.stopDeviceMotionUpdates() }
}
