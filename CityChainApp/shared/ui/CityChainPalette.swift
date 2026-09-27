import SwiftUI

enum CityChainPalette {
  static let sky = Color(red: 0.87, green: 0.93, blue: 0.98)
  static let paper = Color(red: 0.98, green: 0.97, blue: 0.94)
  static let mint = Color(red: 0.88, green: 0.94, blue: 0.89)
  static let blue = Color(red: 0.16, green: 0.32, blue: 0.68)
  static let orange = Color(red: 0.98, green: 0.72, blue: 0.32)
  static let ink = Color(red: 0.09, green: 0.17, blue: 0.27)
  static let lavender = Color(red: 0.51, green: 0.37, blue: 0.76)
  static let secondaryInk = Color(red: 0.36, green: 0.40, blue: 0.45)
  static let teal = Color(red: 0.12, green: 0.43, blue: 0.39)
}

struct CityChainCard: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(20)
      .background(.white, in: RoundedRectangle(cornerRadius: 24))
      .overlay {
        RoundedRectangle(cornerRadius: 24)
          .strokeBorder(CityChainPalette.ink.opacity(0.06), lineWidth: 1)
      }
      .shadow(color: CityChainPalette.ink.opacity(0.04), radius: 12, y: 5)
  }
}

struct CityCapitalBadge: View {
  var body: some View {
    Label {
      Text("State capital")
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    } icon: {
      Image(systemName: "star.fill")
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(CityChainPalette.teal)
    .fixedSize(horizontal: true, vertical: false)
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(CityChainPalette.mint, in: Capsule())
  }
}
