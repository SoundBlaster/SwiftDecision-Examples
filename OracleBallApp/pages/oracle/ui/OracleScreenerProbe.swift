#if DEBUG && ORACLE_SCREENER && targetEnvironment(simulator)
import Foundation
import ScreenerKit
import SwiftUI
import UIKit

/// Explicitly armed, bounded simulator capture; never compiled into the normal app.
struct OracleScreenerProbe: UIViewRepresentable {
  let layout: String
  let sceneSide: Double
  let sceneScale: Double
  let ballCenterY: Double
  let controlsTop: Double

  func makeUIView(context: Context) -> ProbeView { ProbeView() }
  func updateUIView(_ view: ProbeView, context: Context) {
    view.recorder.update(layout: layout, metrics: [
      "scene.side": String(sceneSide), "scene.scale": String(sceneScale),
      "ball.centerY": String(ballCenterY), "controls.top": String(controlsTop)
    ])
  }
  static func dismantleUIView(_ view: ProbeView, coordinator: ()) { view.recorder.attach(to: nil) }

  final class ProbeView: UIView {
    let recorder = OracleScreenerRecorder()
    override func didMoveToWindow() {
      super.didMoveToWindow()
      recorder.attach(to: window)
    }
  }
}

@MainActor
final class OracleScreenerRecorder {
  private static let maxFrames = 40
  private static let maxDuration: Duration = .seconds(180)
  private let screener = Screener()
  private weak var window: UIWindow?
  private var task: Task<Void, Never>?
  private var layout = "unknown"
  private var metrics: [String: String] = [:]
  private var isRecording = false
  private var pendingLayoutChange = false

  func update(layout: String, metrics: [String: String]) {
    self.metrics = metrics
    guard layout != self.layout else { return }
    self.layout = layout
    guard isRecording else { return }
    pendingLayoutChange = true
  }

  func attach(to window: UIWindow?) {
    guard self.window !== window else { return }
    task?.cancel()
    self.window = window
    let mode = ProcessInfo.processInfo.environment["ORACLE_SCREENER_RECORD"]
    guard mode == "1" || mode == "layout",
          let window else { return }
    task = Task { [weak self, weak window] in
      guard let self, let window else { return }
      if mode == "layout" {
        await recordLayoutChanges(window: window)
      } else {
        await record(window: window)
      }
    }
  }

  /// Arm before the user changes pose; each change opens its own short trace.
  private func recordLayoutChanges(window: UIWindow) async {
    let armedAt = ContinuousClock.now
    var baseline = layout
    while !Task.isCancelled && armedAt.duration(to: .now) < .seconds(900) {
      if layout != baseline {
        let before = baseline
        pendingLayoutChange = true
        await record(window: window, triggeredFrom: before)
        baseline = layout
      }
      do { try await Task.sleep(for: .milliseconds(200)) }
      catch { return }
    }
  }

  private func record(window: UIWindow, triggeredFrom: String? = nil) async {
    var started = false
    do {
      let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)
      let directory = caches.appending(path: "OracleScreener/Traces", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let stopFile = directory.deletingLastPathComponent().appending(path: "stop")
      if FileManager.default.fileExists(atPath: stopFile.path) {
        try FileManager.default.removeItem(at: stopFile)
      }
      let trace = try await screener.startSession(name: "Oracle Duo visual trace",
        appBundleID: Bundle.main.bundleIdentifier ?? "OracleScreener", tracesDirectory: directory)
      started = true
      isRecording = true
      print("Oracle Screener trace: \(trace.path)")
      try await screener.mark("oracle.capture.started", metadata: [
        "backend": "UIKitCaptureSource", "layout": layout, "sdk": "0.2.0",
        "triggeredFrom": triggeredFrom ?? "launch"
      ])
      let start = ContinuousClock.now
      var nextPeriodic = start
      var burstRemaining = 0
      var frame = 0
      let duration: Duration = triggeredFrom == nil ? Self.maxDuration : .seconds(6)
      while !Task.isCancelled && frame < Self.maxFrames && start.duration(to: .now) < duration {
        if FileManager.default.fileExists(atPath: stopFile.path) {
          try FileManager.default.removeItem(at: stopFile)
          break
        }
        if pendingLayoutChange {
          pendingLayoutChange = false
          burstRemaining = 8
          try await screener.mark("oracle.layout.changed", metadata: ["layout": layout])
        }
        if burstRemaining > 0 || ContinuousClock.now >= nextPeriodic {
          let isBurst = burstRemaining > 0
          let captured = try UIKitCaptureSource(view: window).capture()
          try await screener.recordFrame(captured, reason: "oracle.sample", metadata: [
            "capture.backend": "UIKitCaptureSource", "layout": layout,
            "trigger": isBurst ? "layout" : "periodic", "sample": String(frame)
          ].merging(metrics) { current, _ in current })
          frame += 1
          if isBurst { burstRemaining -= 1 }
          nextPeriodic = ContinuousClock.now.advanced(by: .seconds(4))
        }
        try await Task.sleep(for: .milliseconds(100))
      }
      try await screener.mark("oracle.capture.completed", metadata: ["frames": String(frame)])
    } catch is CancellationError {
      print("Oracle Screener capture cancelled")
    } catch {
      print("Oracle Screener capture failed: \(error)")
      if started { try? await screener.mark("oracle.capture.failed", metadata: ["error": String(describing: error)]) }
    }
    isRecording = false
    if started {
      do { try await screener.stopSession() }
      catch { print("Oracle Screener stop failed: \(error)") }
    }
  }
}
#endif
