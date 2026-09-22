import OraclePresentation
import RealityKit

/// The only owner of the plate transform and absorption controls.
@MainActor
final class OracleRevealSystem: System {
  private static let query = EntityQuery(where: .has(OracleRevealComponent.self))
  required init(scene: RealityKit.Scene) {}

  func update(context: SceneUpdateContext) {
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
      entity.orientation = frame.orientation
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
}
