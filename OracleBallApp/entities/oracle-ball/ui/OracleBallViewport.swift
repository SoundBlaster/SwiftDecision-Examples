import RealityKit
import SwiftUI

struct OracleBallViewport: View {
  let answer: String
  let requestID: Int
  let answerRequestID: Int
  let terminalRequestID: Int
  let onClear: () -> Void
  let onShake: () -> Void
  let onShakeActivityChanged: (Bool) -> Void
  var isPaused = false
  var isShakeEnabled = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var renderer: OracleScene?
  @State private var renderFailed = false
  @State private var lastHandledRequestID: Int?

  private var shouldPauseScene: Bool {
    isPaused || scenePhase != .active
  }

  var body: some View {
    RealityView { content in
      content.camera = .virtual
      do {
        let scene = try await OracleScene(
          answer: answer,
          reduceMotion: reduceMotion,
          paused: shouldPauseScene,
          shakeEnabled: isShakeEnabled,
          onShake: onShake,
          onShakeActivityChanged: onShakeActivityChanged)
        content.add(scene.root)
        renderer = scene
      } catch {
        renderFailed = true
      }
    } update: { _ in
      renderer?.setEnvironment(reduceMotion: reduceMotion, paused: shouldPauseScene)
      renderer?.setShakeEnabled(isShakeEnabled)
    }
    .task(id: "\(requestID)-\(renderer != nil)") {
      guard let renderer, requestID > 0, lastHandledRequestID != requestID else { return }
      lastHandledRequestID = requestID
      renderer.beginWaiting(request: requestID)
      if terminalRequestID == requestID {
        renderer.cancelWaiting(request: requestID)
      } else if answerRequestID == requestID {
        do {
          try renderer.present(answer: answer, request: requestID)
        } catch {
          renderFailed = true
        }
      }
    }
    .onChange(of: answerRequestID) { _, _ in
      guard let renderer, requestID > 0 else { return }
      guard answerRequestID == requestID else { return }
      do {
        try renderer.present(answer: answer, request: requestID)
      } catch {
        renderFailed = true
      }
    }
    .onChange(of: terminalRequestID) { _, _ in
      guard let renderer, requestID > 0, terminalRequestID == requestID else { return }
      renderer.cancelWaiting(request: requestID)
    }
    .onAppear {
      renderer?.setEnvironment(reduceMotion: reduceMotion, paused: shouldPauseScene)
      renderer?.setShakeEnabled(isShakeEnabled)
    }
    .onDisappear { renderer?.setEnvironment(reduceMotion: reduceMotion, paused: true) }
    .onChange(of: shouldPauseScene) { _, paused in
      renderer?.setEnvironment(reduceMotion: reduceMotion, paused: paused)
    }
    .onChange(of: isShakeEnabled) { _, enabled in
      renderer?.setShakeEnabled(enabled)
    }
    .contentShape(Rectangle())
    .onTapGesture(perform: onClear)
    .overlay {
      if renderFailed {
        ContentUnavailableView(
          "The oracle could not appear", systemImage: "sparkles",
          description: Text("Please reopen the demo to reload the scene.")
        )
        .foregroundStyle(.white)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Magic 8 Ball")
    .accessibilityValue(answer.replacingOccurrences(of: "\n", with: " "))
    .accessibilityHint("Tap to clear the question and answer")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction(.default, onClear)
  }
}
