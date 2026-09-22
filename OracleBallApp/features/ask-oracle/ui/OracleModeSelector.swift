import SwiftUI

enum OracleMode: String, CaseIterable, Identifiable {
  case noul = "Noul"
  case choice = "Choice"
  case score = "Score"

  var id: Self { self }

  var icon: String {
    switch self {
    case .noul: "checkmark.circle.fill"
    case .choice: "list.bullet"
    case .score: "percent"
    }
  }

  var descriptor: String {
    switch self {
    case .noul: "Yes / No"
    case .choice: "Phrase"
    case .score: "Confidence"
    }
  }

  var sampleAnswer: String {
    switch self {
    case .noul: "Definitely\nyes"
    case .choice: "Ask again\nlater"
    case .score: "87%"
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
              Text(mode.rawValue)
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
        .accessibilityLabel("\(mode.rawValue) mode, \(mode.descriptor)")
      }
    }
    .padding(4)
    .oraclePillBackground()
    .frame(maxWidth: 360)
  }
}
