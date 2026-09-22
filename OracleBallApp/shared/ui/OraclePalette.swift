import SwiftUI

extension Color {
  static let oracleInk = Color(red: 0.025, green: 0.018, blue: 0.055)
  static let oraclePanel = Color(red: 0.075, green: 0.045, blue: 0.125)
  static let oraclePurple = Color(red: 0.62, green: 0.28, blue: 0.96)
  static let oracleLavender = Color(red: 0.82, green: 0.68, blue: 1.0)
}

struct OraclePillBackground: ViewModifier {
  func body(content: Content) -> some View {
    content
      .background(.ultraThinMaterial, in: Capsule())
      .overlay {
        Capsule().strokeBorder(.white.opacity(0.11), lineWidth: 1)
      }
  }
}

extension View {
  func oraclePillBackground() -> some View {
    modifier(OraclePillBackground())
  }
}
