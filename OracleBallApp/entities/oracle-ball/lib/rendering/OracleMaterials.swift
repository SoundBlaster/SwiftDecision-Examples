import Metal
import RealityKit
import UIKit

@MainActor
enum OracleMaterials {
  static func shell() -> PhysicallyBasedMaterial {
    var material = PhysicallyBasedMaterial()
    material.baseColor = .init(tint: UIColor(white: 0.012, alpha: 1))
    material.metallic = .init(floatLiteral: 0.12)
    material.roughness = .init(floatLiteral: 0.12)
    material.clearcoat = .init(floatLiteral: 1)
    material.clearcoatRoughness = .init(floatLiteral: 0.07)
    return material
  }

  static func rim() -> PhysicallyBasedMaterial {
    var material = shell()
    material.baseColor = .init(tint: UIColor(red: 0.025, green: 0.022, blue: 0.042, alpha: 1))
    material.metallic = .init(floatLiteral: 0.65)
    material.roughness = .init(floatLiteral: 0.22)
    return material
  }

  static func cavity() -> UnlitMaterial {
    var material = UnlitMaterial(
      color: UIColor(red: 0.013, green: 0.019, blue: 0.078, alpha: 1))
    material.blending = .opaque
    // The shared shell mesh faces outward; only its inside should draw this material.
    material.faceCulling = .front
    return material
  }

  static func glass() -> PhysicallyBasedMaterial {
    var material = PhysicallyBasedMaterial()
    material.baseColor = .init(tint: UIColor(red: 0.11, green: 0.075, blue: 0.22, alpha: 1))
    material.roughness = .init(floatLiteral: 0.06)
    material.blending = .transparent(opacity: .init(floatLiteral: 0.065))
    material.faceCulling = .back
    return material
  }

  static func windowShadow() throws -> CustomMaterial {
    var material = try custom(named: "oracleWindowShadow")
    material.blending = .transparent(opacity: .init(floatLiteral: 1))
    material.faceCulling = .back
    // Clear central radius, outer radius, maximum edge opacity.
    material.custom.value = [0.42, 1, 0.92, 0]
    return material
  }

  static func ringReflection() throws -> CustomMaterial {
    var material = try custom(named: "oracleRingReflection")
    material.blending = .transparent(opacity: .init(floatLiteral: 1))
    material.faceCulling = .back
    material.custom.value = .zero
    return material
  }

  static func face(textures: OracleAnswerTexture.Pair) throws -> CustomMaterial {
    var material = try custom(named: "oracleFace")
    material.baseColor = .init(texture: .init(textures.sharp))
    material.custom.texture = .init(textures.blurred)
    return material
  }

  static func edge() throws -> CustomMaterial { try custom(named: "oracleEdge") }

  private static func custom(named name: String) throws -> CustomMaterial {
    guard let library = MTLCreateSystemDefaultDevice()?.makeDefaultLibrary() else {
      throw OracleRenderError.missingMetalLibrary
    }
    var material = try CustomMaterial(
      surfaceShader: .init(named: name, in: library), lightingModel: .unlit)
    material.custom.value = [0.804, 8, 2.2, 0]
    return material
  }
}
