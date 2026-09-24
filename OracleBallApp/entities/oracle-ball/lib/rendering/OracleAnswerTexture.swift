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

  static func make(answer: String, fontScale: CGFloat = 1) throws -> Pair {
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
          UIColor(red: 0.12, green: 0.045, blue: 0.72, alpha: 1).cgColor,
          UIColor(red: 0.10, green: 0.035, blue: 0.62, alpha: 1).cgColor,
        ] as CFArray
      if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])
      {
        cg.drawLinearGradient(
          gradient, start: CGPoint(x: 384, y: 0), end: CGPoint(x: 384, y: 768), options: [])
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
      let baseFontSize: CGFloat = label.count <= 5 ? 100 : (label.count > 24 ? 45 : 58)
      let fontSize = baseFontSize * max(fontScale, 0.5)
      let rect = CGRect(x: 112, y: 175, width: 544, height: 245)
      let fittedFontSize = largestFontSize(
        fitting: label,
        maximumSize: fontSize,
        in: rect,
        paragraph: paragraph)
      let fittedFont = UIFont.systemFont(ofSize: fittedFontSize, weight: .medium)
      let attributes: [NSAttributedString.Key: Any] = [
        .font: fittedFont,
        .foregroundColor: UIColor(red: 0.89, green: 0.88, blue: 1, alpha: 1),
        .paragraphStyle: paragraph,
      ]
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

  private static func largestFontSize(
    fitting text: String,
    maximumSize: CGFloat,
    in rect: CGRect,
    paragraph: NSParagraphStyle
  ) -> CGFloat {
    var lowerBound: CGFloat = 1
    var upperBound = maximumSize

    for _ in 0..<16 {
      let candidate = (lowerBound + upperBound) / 2
      let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: candidate, weight: .medium),
        .paragraphStyle: paragraph,
      ]
      let measured = (text as NSString).boundingRect(
        with: rect.size,
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: attributes,
        context: nil)

      if measured.width <= rect.width && measured.height <= rect.height {
        lowerBound = candidate
      } else {
        upperBound = candidate
      }
    }

    return lowerBound
  }
}

enum OracleRenderError: Error {
  case missingMetalLibrary
  case textureCreation
}
