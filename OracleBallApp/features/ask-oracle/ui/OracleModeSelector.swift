import SwiftUI
import OracleGame
extension OracleMode {
  var localizedName: String {
    String(localized: String.LocalizationValue(rawValue))
  }

  var icon: String {
    switch self {
    case .automatic: "wand.and.stars"
    case .noul: "checkmark.circle.fill"
    case .choice: "list.bullet"
    case .score: "percent"
    case .unsupported: "questionmark"
    }
  }

  var descriptor: String {
    switch self {
    case .automatic: String(localized: "Auto")
    case .noul: String(localized: "Yes / No")
    case .choice: String(localized: "Phrase")
    case .score: String(localized: "Confidence")
    case .unsupported: String(localized: "No answer")
    }
  }

}

struct OracleModeSelector: View {
  @Binding var selection: OracleMode

  var body: some View {
    HStack(spacing: 4) {
      ForEach(OracleMode.allCases) { mode in
        Button {
          selection = mode
        } label: {
          Label {
            VStack(alignment: .leading, spacing: 1) {
              Text(mode.localizedName)
                .font(.caption.weight(.semibold))
              Text(mode.descriptor)
                .font(.caption2)
                .foregroundStyle(.white.opacity(selection == mode ? 0.62 : 0.34))
            }
          } icon: {
            Image(systemName: mode.icon)
              .font(.caption.weight(.semibold))
          }
          .foregroundStyle(selection == mode ? .white : .white.opacity(0.48))
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .padding(.horizontal, 8)
          .background {
            if selection == mode {
              Capsule().fill(.white.opacity(0.13))
            }
          }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == mode ? .isSelected : [])
        .accessibilityLabel("\(mode.localizedName) · \(mode.descriptor)")
      }
    }
    .padding(4)
    .oraclePillBackground()
    .frame(maxWidth: 360)
  }
}
