import SwiftUI

struct AskOracleField: View {
  @Binding var text: String
  let onSubmit: () -> Void

  @FocusState private var isFocused: Bool

  private func submit() {
    isFocused = false
    onSubmit()
  }

  var body: some View {
    HStack(spacing: 10) {
      TextField("Ask the oracle", text: $text)
        .lineLimit(1)
        .font(.body.weight(.medium))
        .foregroundStyle(.white)
        .tint(.oracleLavender)
        .focused($isFocused)
        .submitLabel(.send)
        .onSubmit(submit)
        .accessibilityLabel("Question for the oracle")
        .accessibilityHint("Type a question, or submit an empty field to replay the demo")

      Button(action: submit) {
        Image(systemName: "arrow.up")
          .font(.headline.weight(.bold))
          .frame(width: 44, height: 44)
          .foregroundStyle(.white)
          .background(
            LinearGradient(
              colors: [.oraclePurple, .purple.opacity(0.7)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ), in: Circle()
          )
          .shadow(color: .oraclePurple.opacity(0.35), radius: 12, y: 4)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Reveal answer")
      .accessibilityHint("Shows the deterministic demo answer for the selected mode")
    }
    .padding(.leading, 18)
    .padding(.trailing, 7)
    .padding(.vertical, 7)
    .background(
      Color.oraclePanel.opacity(0.88), in: RoundedRectangle(cornerRadius: 22, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .strokeBorder(.white.opacity(isFocused ? 0.26 : 0.12), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    .animation(.easeOut(duration: 0.18), value: isFocused)
  }
}
