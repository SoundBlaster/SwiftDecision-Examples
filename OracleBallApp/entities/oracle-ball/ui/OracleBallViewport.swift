import RealityKit
import SwiftUI

struct OracleBallViewport: View {
  let answer: String
  let requestID: Int
  let answerRequestID: Int
  let terminalRequestID: Int
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var renderer: OracleScene?
  @State private var renderFailed = false

  var body: some View {
    RealityView { content in
      content.camera = .virtual
      do {
        let scene = try await OracleScene(
          answer: answer, reduceMotion: reduceMotion, paused: scenePhase != .active)
        content.add(scene.root)
        renderer = scene
      } catch {
        renderFailed = true
      }
    } update: { _ in
      renderer?.setEnvironment(reduceMotion: reduceMotion, paused: scenePhase != .active)
    }
    .task(id: "\(requestID)-\(renderer != nil)") {
      guard let renderer, requestID > 0 else { return }
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
    .onAppear { renderer?.setEnvironment(reduceMotion: reduceMotion, paused: scenePhase != .active) }
    .onDisappear { renderer?.setEnvironment(reduceMotion: reduceMotion, paused: true) }
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
  }
}
