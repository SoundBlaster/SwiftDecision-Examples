import Metal
import RealityKit
import simd

/// The field is rooted in the scene, so the ball can float above it independently.
@MainActor
enum OracleField {
  static func make(reduceMotion: Bool, paused: Bool) throws -> Entity {
    let field = Entity()
    field.name = "AntigravityField"
    let ringStack = Entity()
    ringStack.name = "Coaxial field rings"
    // Local Z points straight up; perspective alone gives the horizontal rings their oval shape.
    ringStack.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
    ringStack.position.y = -1.08
    field.addChild(ringStack)
    let ringMesh = try OracleFieldMesh.ring(halfWidth: 0.11)
    let ringMaterial = try material(color: [0.72, 0.38, 1], strength: 1)
    let pulses: [Entity] = (0..<2).map { index in
      let pulse = ring(mesh: ringMesh, material: ringMaterial)
      pulse.name = "Rising ring \(index + 1)"
      place(pulse, radius: 0.58)
      pulse.components.set(OpacityComponent(opacity: 0))
      ringStack.addChild(pulse)
      return pulse
    }

    field.components.set(OracleFieldComponent(
      pulses: pulses,
      reduceMotion: reduceMotion, isPaused: paused))
    return field
  }

  private static func ring(mesh: MeshResource, material: CustomMaterial) -> Entity {
    let ring = Entity()
    ring.addChild(ModelEntity(mesh: mesh, materials: [material]))
    return ring
  }

  /// All rings share local Z. Larger radii sit farther along it, above smaller ones.
  static func place(_ ring: Entity, radius: Float) {
    let rise = (radius - 0.54) * 0.72
    ring.scale = SIMD3<Float>(repeating: radius)
    ring.position = [0, 0, rise]
  }

  private static func material(color: SIMD3<Float>, strength: Float) throws -> CustomMaterial {
    guard let library = MTLCreateSystemDefaultDevice()?.makeDefaultLibrary() else {
      throw OracleRenderError.missingMetalLibrary
    }
    var material = try CustomMaterial(
      surfaceShader: .init(named: "oracleFieldRibbon", in: library), lightingModel: .unlit)
    material.blending = .transparent(opacity: .init(floatLiteral: 1))
    material.faceCulling = .back
    material.custom.value = [color.x, color.y, color.z, strength]
    return material
  }
}
