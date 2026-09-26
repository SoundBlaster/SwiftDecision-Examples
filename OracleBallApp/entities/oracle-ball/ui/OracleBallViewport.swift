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
  let onDragEnded: () -> Void
  let onDragMovement: () -> Void
  var isPaused = false
  var isShakeEnabled = true
  @ScaledMetric(relativeTo: .body) private var answerFontScale: CGFloat = 1
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var renderer: OracleScene?
  @State private var renderFailed = false
  @State private var lastHandledRequestID: Int?

  private var shouldPauseScene: Bool {
    isPaused || scenePhase != .active
  }

  private var rendererTaskID: String {
    "\(requestID)-\(renderer != nil)"
  }

  private func finishDragInteraction() {
    renderer?.releaseBall()
    onDragEnded()
  }

  private func updateBallDrag(_ translation: CGPoint, _ size: CGSize) {
    renderer?.dragBall(
      translation: [Float(translation.x), Float(translation.y)],
      viewportSide: Float(min(size.width, size.height)))
  }

  private var ballGestureLayer: some View {
    OracleBallGestureLayer(
      onTap: onClear,
      onDragChanged: updateBallDrag,
      onDragMoved: onDragMovement,
      onDragEnded: finishDragInteraction)
      .accessibilityHidden(true)
  }

  var body: some View {
    RealityView { content in
      content.camera = .virtual
      do {
        let scene = try await OracleScene(
          answer: answer,
          answerFontScale: answerFontScale,
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
    .task(id: rendererTaskID) {
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
    .onChange(of: answerFontScale) { _, scale in
      guard let renderer else { return }
      do {
        try renderer.setAnswerFontScale(scale, answer: answer)
      } catch {
        renderFailed = true
      }
    }
    .onAppear {
      renderer?.setEnvironment(reduceMotion: reduceMotion, paused: shouldPauseScene)
      renderer?.setShakeEnabled(isShakeEnabled)
    }
    .onDisappear {
      finishDragInteraction()
      renderer?.setEnvironment(reduceMotion: reduceMotion, paused: true)
    }
    .onChange(of: shouldPauseScene) { _, paused in
      if paused {
        finishDragInteraction()
      }
      renderer?.setEnvironment(reduceMotion: reduceMotion, paused: paused)
    }
    .onChange(of: isShakeEnabled) { _, enabled in
      renderer?.setShakeEnabled(enabled)
    }
    .contentShape(Rectangle())
    .overlay { ballGestureLayer }
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
    .accessibilityHint("Drag with one finger to tilt. Tap to clear.")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction(.default, onClear)
  }
}
