import OraclePresentation
import RealityKit
import simd

/// Owns camera parallax, lighting, and the plate transform and absorption controls.
@MainActor
final class OracleRevealSystem: System {
  private static let query = EntityQuery(where: .has(OracleRevealComponent.self))
  private static let motionQuery = EntityQuery(where: .has(OracleMotionComponent.self))
  required init(scene: RealityKit.Scene) {}

  func update(context: SceneUpdateContext) {
    updateMotion(context: context)
    for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
      guard var state = entity.components[OracleRevealComponent.self], !state.isPaused else {
        continue
      }
      state.elapsed += max(0, context.deltaTime)
      let duration = state.reduceMotion ? 0.25 : 1.4
      let sampleTime: Double
      switch state.phase {
      case .submerging:
        let retreatDuration = state.reduceMotion ? 0.2 : 0.5
        sampleTime = state.retreatFrom * max(0, 1 - state.elapsed / retreatDuration)
        if state.elapsed >= retreatDuration {
          state.phase = .stirring
          state.elapsed = 0
        }
      case .stirring:
        sampleTime = 0
        if state.answerReady,
          let incoming = entity.findEntity(named: "IncomingFace") as? ModelEntity,
          let face = entity.findEntity(named: "AnswerFace") as? ModelEntity
        {
          face.model = incoming.model
          state.answerReady = false
          state.phase = .revealing
          state.elapsed = 0
        }
      case .revealing:
        sampleTime = state.elapsed
        if state.elapsed >= duration {
          state.phase = .holding
          state.elapsed -= duration
        }
      case .holding:
        sampleTime = duration + state.elapsed
      }
      let frame = TriangleReveal.sample(elapsed: sampleTime, reduceMotion: state.reduceMotion)
      entity.position = frame.position
      let tilt = state.reduceMotion ? .zero
        : entity.parent?.parent?.components[OracleMotionComponent.self]?.tilt ?? SIMD2<Float>.zero
      let response = frame.clarity * 0.28
      entity.orientation = simd_quatf(angle: -tilt.y * response, axis: [1, 0, 0])
        * simd_quatf(angle: tilt.x * response, axis: [0, 1, 0]) * frame.orientation
      for child in entity.children {
        guard var model = child.components[ModelComponent.self] else { continue }
        for index in model.materials.indices {
          guard var material = model.materials[index] as? CustomMaterial else { continue }
          material.custom.value = [frame.fogDistance, 8, 2.2, frame.clarity]
          model.materials[index] = material
        }
        child.components.set(model)
      }
      entity.components.set(state)
    }
  }

  private func updateMotion(context: SceneUpdateContext) {
    for root in context.entities(matching: Self.motionQuery, updatingSystemWhen: .rendering) {
      guard var state = root.components[OracleMotionComponent.self], !state.isPaused else {
        continue
      }
      let dt = max(0, min(context.deltaTime, 0.1))
      state.elapsed += dt
      let sampledTilt = state.input.sample()
      state.tilt = state.reduceMotion ? .zero : OracleParallax.smooth(
        current: state.tilt, target: sampledTilt, deltaTime: dt)
      let tilt = state.tilt
      // A moving viewpoint reveals the rim, glass and plate at different depths.
      let position = SIMD3<Float>(tilt.x * 0.8, tilt.y * 0.6, 3.55)
      state.camera.look(at: .zero, from: position, relativeTo: root)
      let time = Float(state.elapsed)
      // Move the complete ball together; the camera and ground halo stay fixed.
      state.ball.position.y = state.reduceMotion ? 0 : 0.025 * sin(time * 0.9)
      let drift: SIMD2<Float> = state.reduceMotion ? .zero
        : [0.10 * sin(time * 0.23), 0.045 * sin(time * 0.3)]
      state.lighting.orientation = simd_quatf(angle: tilt.x * 0.9 + drift.x, axis: [0, 1, 0])
        * simd_quatf(angle: tilt.y * 0.6 + drift.y, axis: [1, 0, 0])
      // Keep the decorative silhouette ring tangent to the sphere as the camera moves.
      let direction = simd_normalize(position - state.ball.position)
      state.contour.position = direction * 0.282
      state.contour.orientation = simd_quatf(from: [0, 0, 1], to: direction)
      root.components.set(state)
    }
  }
}
