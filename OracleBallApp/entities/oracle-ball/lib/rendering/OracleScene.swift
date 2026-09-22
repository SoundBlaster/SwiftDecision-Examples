import RealityKit
import UIKit

/// Rendering boundary: accepts presentation commands, with no knowledge of decision providers.
@MainActor
final class OracleScene {
  let root = Entity()
  private let plate = Entity()
  private let motion = OracleMotionInput()
  private let incoming: ModelEntity
  private var lastRequest = -1

  init(answer: String, reduceMotion: Bool, paused: Bool) async throws {
    root.name = "Oracle scene"
    let camera = PerspectiveCamera()
    camera.camera.fieldOfViewInDegrees = 40
    camera.position = [0, 0, 3.55]
    root.addChild(camera)

    let ball = Entity()
    ball.name = "BallRoot"
    root.addChild(ball)
    let shell = ModelEntity(mesh: try OracleMesh.shell(), materials: [OracleMaterials.shell()])
    shell.name = "Shell with open window"
    ball.addChild(shell)

    var contourMaterial = OracleMaterials.rim()
    contourMaterial.emissiveColor = .init(
      color: UIColor(red: 0.12, green: 0.055, blue: 0.35, alpha: 1))
    contourMaterial.emissiveIntensity = 0.7
    let contour = ModelEntity(
      mesh: try OracleMesh.ring(radius: 0.958, tube: 0.004), materials: [contourMaterial])
    contour.position.z = 0.282
    contour.name = "Violet silhouette"
    ball.addChild(contour)

    let rim = ModelEntity(
      mesh: try OracleMesh.ring(radius: 0.522, tube: 0.028), materials: [OracleMaterials.rim()])
    rim.position.z = 0.854
    rim.name = "WindowRim"
    ball.addChild(rim)
    let innerRing = ModelEntity(
      mesh: try OracleMesh.ring(radius: 0.498, tube: 0.009), materials: [OracleMaterials.shell()])
    innerRing.position.z = 0.84
    ball.addChild(innerRing)

    // A back wall, well behind the entire plate travel, closes the view into the ball.
    let dark = UnlitMaterial(color: UIColor(red: 0.013, green: 0.019, blue: 0.078, alpha: 1))
    let cavity = ModelEntity(mesh: .generateSphere(radius: 0.8), materials: [dark])
    cavity.scale = [1, 1, 0.015]
    cavity.position.z = -0.25
    cavity.name = "InnerBackground"
    ball.addChild(cavity)

    let faceMesh = try OracleMesh.triangle()
    let material = try OracleMaterials.face(textures: OracleAnswerTexture.make(answer: answer))
    let face = ModelEntity(mesh: faceMesh, materials: [material])
    face.name = "AnswerFace"
    plate.addChild(face)
    incoming = ModelEntity(mesh: faceMesh, materials: [material])
    incoming.name = "IncomingFace"
    incoming.isEnabled = false
    plate.addChild(incoming)
    let edges = ModelEntity(
      mesh: try OracleMesh.triangleSides(), materials: [try OracleMaterials.edge()])
    edges.name = "PlateEdges"
    plate.addChild(edges)
    plate.name = "FloatingPlate"
    plate.components.set(OracleRevealComponent(reduceMotion: reduceMotion, isPaused: paused))
    ball.addChild(plate)

    let windowShadow = ModelEntity(
      mesh: try OracleMesh.windowDisk(radius: 0.497),
      materials: [try OracleMaterials.windowShadow()])
    windowShadow.position.z = 0.853
    windowShadow.name = "Soft window shadow"
    ball.addChild(windowShadow)

    let glass = ModelEntity(
      mesh: .generateSphere(radius: 0.492), materials: [OracleMaterials.glass()])
    glass.scale = [1, 1, 0.025]
    glass.position.z = 0.874
    glass.name = "WindowGlass"
    ball.addChild(glass)
    let lighting = try await OracleLighting.install(on: ball)
    root.components.set(OracleMotionComponent(
      input: motion, camera: camera, lighting: lighting, contour: contour,
      reduceMotion: reduceMotion, isPaused: paused))
    motion.setActive(!paused && !reduceMotion)
  }

  func setEnvironment(reduceMotion: Bool, paused: Bool) {
    motion.setActive(!paused && !reduceMotion)
    if var state = root.components[OracleMotionComponent.self] {
      state.reduceMotion = reduceMotion
      state.isPaused = paused
      root.components.set(state)
    }
    guard var state = plate.components[OracleRevealComponent.self] else { return }
    state.reduceMotion = reduceMotion
    state.isPaused = paused
    plate.components.set(state)
  }

  func beginWaiting(request: Int) {
    lastRequest = request
    guard var state = plate.components[OracleRevealComponent.self] else { return }
    let revealDuration = state.reduceMotion ? 0.25 : 1.4
    switch state.phase {
    case .holding: state.retreatFrom = revealDuration
    case .revealing: state.retreatFrom = min(revealDuration, state.elapsed)
    case .stirring: state.retreatFrom = 0
    case .submerging:
      state.retreatFrom *= max(0, 1 - state.elapsed / (state.reduceMotion ? 0.2 : 0.5))
    }
    state.phase = .submerging
    state.elapsed = 0
    state.answerReady = false
    plate.components.set(state)
  }

  /// Stage the new texture; the render system swaps it only after the old plate has submerged.
  func present(answer: String, request: Int) throws {
    guard request == lastRequest else { return }
    incoming.model?.materials = [
      try OracleMaterials.face(textures: OracleAnswerTexture.make(answer: answer))
    ]
    guard var state = plate.components[OracleRevealComponent.self] else { return }
    state.answerReady = true
    plate.components.set(state)
  }
}
