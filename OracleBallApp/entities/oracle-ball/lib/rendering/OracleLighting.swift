import RealityKit
import UIKit

@MainActor
enum OracleLighting {
  /// A small, deterministic studio environment supplies broad specular reflections.
  static func install(on root: Entity) async throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 512), format: format)
      .image { renderer in
        let cg = renderer.cgContext
        UIColor(white: 0.015, alpha: 1).setFill()
        cg.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
        UIColor(red: 0.83, green: 0.87, blue: 1, alpha: 1).setFill()
        cg.fill(CGRect(x: 260, y: 95, width: 360, height: 38))
        UIColor(red: 0.43, green: 0.37, blue: 1, alpha: 1).setFill()
        cg.fill(CGRect(x: 710, y: 100, width: 75, height: 260))
        UIColor(red: 0.29, green: 0.17, blue: 0.65, alpha: 1).setFill()
        cg.fill(CGRect(x: 80, y: 180, width: 35, height: 150))
        UIColor(red: 0.33, green: 0.28, blue: 0.53, alpha: 1).setFill()
        cg.fill(CGRect(x: 320, y: 365, width: 310, height: 12))
        UIColor(red: 0.60, green: 0.50, blue: 0.80, alpha: 1).setFill()
        cg.fill(CGRect(x: 960, y: 140, width: 18, height: 230))
      }
    guard let cgImage = image.cgImage else { throw OracleRenderError.textureCreation }
    let environment = try await EnvironmentResource(equirectangular: cgImage)
    let lighting = Entity()
    lighting.name = "Studio environment"
    lighting.components.set(
      ImageBasedLightComponent(source: .single(environment), intensityExponent: 1.3))
    root.addChild(lighting)
    root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: lighting))

    let key = DirectionalLight()
    key.light.color = UIColor(red: 0.76, green: 0.8, blue: 1, alpha: 1)
    key.light.intensity = 1500
    key.look(at: .zero, from: [-2, 3, 3], relativeTo: nil)
    root.addChild(key)
    let rim = PointLight()
    rim.light.color = UIColor(red: 0.36, green: 0.13, blue: 1, alpha: 1)
    rim.light.intensity = 900
    rim.light.attenuationRadius = 5
    rim.position = [1.3, 0.7, -0.4]
    root.addChild(rim)
  }
}
