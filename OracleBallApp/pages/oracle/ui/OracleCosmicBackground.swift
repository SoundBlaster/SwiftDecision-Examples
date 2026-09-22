import SwiftUI

struct OracleCosmicBackground: View {
  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Color.oracleInk

        Image("OracleNebula")
          .resizable()
          .scaledToFill()
          .frame(width: proxy.size.width, height: proxy.size.height)
          .opacity(0.78)
          .overlay(Color.black.opacity(0.2))

        Canvas { context, size in
          let rect = CGRect(origin: .zero, size: size)
          context.fill(
            Path(rect),
            with: .linearGradient(
              Gradient(colors: [Color.black.opacity(0.15), .clear, Color.black.opacity(0.38)]),
              startPoint: CGPoint(x: size.width * 0.1, y: 0),
              endPoint: CGPoint(x: size.width * 0.9, y: size.height)
            ))

          var seed: UInt64 = 0x4F52_4143_4C45
          for index in 0..<110 {
            seed = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493
            let x = CGFloat(seed % 10_000) / 10_000 * size.width
            seed = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493
            let y = CGFloat(seed % 10_000) / 10_000 * size.height
            let radius = index.isMultiple(of: 13) ? 1.15 : (index.isMultiple(of: 5) ? 0.8 : 0.42)
            let opacity = index.isMultiple(of: 7) ? 0.74 : 0.38
            context.fill(
              Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
              with: .color(.white.opacity(opacity)))
          }
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .clipped()
    }
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }
}
