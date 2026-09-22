import CoreImage
import RealityKit
import UIKit

/// Text is rasterized once per answer, then follows the plate's perspective and occlusion.
@MainActor
enum OracleAnswerTexture {
  struct Pair {
    let sharp: TextureResource
    let blurred: TextureResource
  }

  private static let context = CIContext()

  static func make(answer: String) throws -> Pair {
    let size = CGSize(width: 768, height: 768)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
      let cg = renderer.cgContext
      cg.setFillColor(UIColor(red: 0.022, green: 0.008, blue: 0.10, alpha: 1).cgColor)
      cg.fill(CGRect(origin: .zero, size: size))
      let colors =
        [
          UIColor(red: 0.17, green: 0.055, blue: 0.94, alpha: 1).cgColor,
          UIColor(red: 0.035, green: 0.014, blue: 0.26, alpha: 1).cgColor,
        ] as CFArray
      if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])
      {
        cg.drawRadialGradient(
          gradient, startCenter: CGPoint(x: 384, y: 170), startRadius: 0,
          endCenter: CGPoint(x: 384, y: 250), endRadius: 570, options: .drawsAfterEndLocation)
      }
      // Fixed flecks give the translucent blue face a subtle mineral texture.
      for index in 0..<140 {
        let x = CGFloat((index * 173 + 41) % 768)
        let y = CGFloat((index * 317 + 29) % 768)
        cg.setFillColor(UIColor(white: 1, alpha: index % 7 == 0 ? 0.16 : 0.035).cgColor)
        cg.fillEllipse(in: CGRect(x: x, y: y, width: 1.4, height: 1.4))
      }
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .center
      paragraph.lineSpacing = 8
      // Bound caller text; long explanations belong outside the viewport.
      let label = String(answer.prefix(48))
      let fontSize: CGFloat = label.count <= 5 ? 100 : (label.count > 24 ? 45 : 58)
      let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
        .foregroundColor: UIColor(red: 0.89, green: 0.88, blue: 1, alpha: 1),
        .paragraphStyle: paragraph,
      ]
      let rect = CGRect(x: 112, y: 175, width: 544, height: 245)
      (label as NSString).draw(in: rect, withAttributes: attributes)
    }
    guard let sharpImage = image.cgImage else { throw OracleRenderError.textureCreation }
    let input = CIImage(cgImage: sharpImage)
    let blurred = input.clampedToExtent().applyingFilter(
      "CIGaussianBlur", parameters: [kCIInputRadiusKey: 18]
    ).cropped(to: input.extent)
    guard let blurredImage = context.createCGImage(blurred, from: input.extent) else {
      throw OracleRenderError.textureCreation
    }
    return try Pair(
      sharp: TextureResource(image: sharpImage, options: .init(semantic: .color)),
      blurred: TextureResource(image: blurredImage, options: .init(semantic: .color))
    )
  }
}

enum OracleRenderError: Error {
  case missingMetalLibrary
  case textureCreation
}
