import RealityKit

/// Animates the grounded field independently of the floating ball.
@MainActor
final class OracleFieldSystem: System {
  private static let query = EntityQuery(where: .has(OracleFieldComponent.self))
  required init(scene: RealityKit.Scene) {}

  func update(context: SceneUpdateContext) {
    for field in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
      guard var state = field.components[OracleFieldComponent.self], !state.isPaused else {
        continue
      }
      state.elapsed += max(0, min(context.deltaTime, 0.1))
      let time = Float(state.elapsed)

      if state.reduceMotion {
        for pulse in state.pulses {
          pulse.components.set(OpacityComponent(opacity: 0))
        }
      } else {
        for (index, pulse) in state.pulses.enumerated() {
          let offset = Float(index) / Float(state.pulses.count)
          let progress = (time / 6.5 + offset).truncatingRemainder(dividingBy: 1)
          let radius = 0.58 + 0.34 * progress
          OracleField.place(pulse, radius: radius)
          let glow = sin(.pi * progress)
          pulse.components.set(OpacityComponent(opacity: 0.56 * glow * glow))
        }
      }
      if let reflection = state.windowReflection,
        var model = reflection.model,
        var material = model.materials.first as? CustomMaterial {
        // Two radius/opacity pairs describe the same pulses drawn in the scene.
        var rings = SIMD4<Float>.zero
        for (index, pulse) in state.pulses.prefix(2).enumerated() {
          rings[index * 2] = pulse.scale.x
          rings[index * 2 + 1] = pulse.components[OpacityComponent.self]?.opacity ?? 0
        }
        material.custom.value = rings
        model.materials = [material]
        reflection.model = model
      }
      field.components.set(state)
    }
  }
}
