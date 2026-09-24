import SwiftUI
import NestedA11yIDs

struct AskOracleField: View {
  @Binding var text: String
  @FocusState.Binding var isFocused: Bool
  @ScaledMetric(relativeTo: .body) private var submitButtonSize: CGFloat = 44
  let isSubmitting: Bool
  let onSubmit: () -> Void

  private func submit() {
    guard !isSubmitting else { return }
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
        .nestedAccessibilityIdentifier("input")

      Button(action: submit) {
        ZStack {
          if isSubmitting {
            ProgressView()
              .progressViewStyle(.circular)
              .tint(.white)
              .transition(.opacity.combined(with: .scale(scale: 0.8)))
          } else {
            Image(systemName: "arrow.up")
              .font(.headline.weight(.bold))
              .transition(.opacity.combined(with: .scale(scale: 0.8)))
          }
        }
        .frame(width: submitButtonSize, height: submitButtonSize)
        .foregroundStyle(.white)
        .background(
          LinearGradient(
            colors: [.oraclePurple, .purple.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ), in: Circle()
        )
        .shadow(color: .oraclePurple.opacity(0.35), radius: 12, y: 4)
        .animation(.easeInOut(duration: 0.2), value: isSubmitting)
      }
      .buttonStyle(.plain)
      .disabled(isSubmitting)
      .accessibilityLabel(isSubmitting ? "Waiting for answer" : "Reveal answer")
      .accessibilityHint(
        isSubmitting
          ? "The oracle is preparing an answer"
          : "The oracle chooses the answer format automatically")
      .nestedAccessibilityIdentifier("submit")
    }
    .padding(.leading, 18)
    .padding(.trailing, 7)
    .padding(.vertical, 7)
    .background(Color.oraclePanel.opacity(0.88), in: Capsule())
    .overlay {
      Capsule()
        .strokeBorder(.white.opacity(isFocused ? 0.26 : 0.12), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    .animation(.easeOut(duration: 0.18), value: isFocused)
    .nestedAccessibilityIdentifier("question")
  }
}
