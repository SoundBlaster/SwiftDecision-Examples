import RealityKit
import SwiftUI

struct OracleBallViewport: View {
  let answer: String
  let revealID: Int
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
    .task(id: "\(revealID)-\(renderer != nil)") {
      guard let renderer, revealID > 0 else { return }
      renderer.beginWaiting(request: revealID)
      do {
        // Presentation demo only. A future provider calls present when its result arrives.
        try await Task.sleep(for: .milliseconds(750))
        try Task.checkCancellation()
        try renderer.present(answer: answer, request: revealID)
      } catch is CancellationError {
        // A newer request owns the scene now.
      } catch {
        renderFailed = true
      }
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
