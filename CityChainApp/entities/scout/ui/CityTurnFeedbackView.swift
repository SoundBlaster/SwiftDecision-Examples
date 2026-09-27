import SwiftUI

/// Dismissible Scout feedback shown next to the active game surface.
struct CityTurnFeedbackView: View {
  let message: String
  let presentation: ScoutPresentation
  let isFinished: Bool
  var maximumHeight: CGFloat? = nil
  let onDismiss: () -> Void
  @State private var contentHeight: CGFloat = 44

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      if let maximumHeight {
        ScrollView {
          CityTurnFeedbackContent(
            message: message, presentation: presentation,
            isFinished: isFinished, isCompact: true)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
              contentHeight = height
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(contentHeight, maximumHeight))
      } else {
        CityTurnFeedbackContent(
          message: message, presentation: presentation,
          isFinished: isFinished, isCompact: false)
      }

      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(CityChainPalette.secondaryInk)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Dismiss message")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      presentation.pose == .tryAnother
        ? Color(red: 1, green: 0.94, blue: 0.82) : .white,
      in: RoundedRectangle(cornerRadius: 18))
    .simultaneousGesture(
      DragGesture(minimumDistance: 30).onEnded { value in
        let horizontal = abs(value.translation.width)
        if horizontal > 60 && horizontal > abs(value.translation.height) * 1.5 {
          onDismiss()
        }
      }
    )
    .accessibilityAction(named: "Dismiss message", onDismiss)
  }
}

private struct CityTurnFeedbackContent: View {
  let message: String
  let presentation: ScoutPresentation
  let isFinished: Bool
  let isCompact: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      if isCompact {
        Image(systemName: "exclamationmark.circle")
          .foregroundStyle(CityChainPalette.ink)
          .accessibilityHidden(true)
      } else {
        ScoutView(presentation: presentation)
          .frame(width: 52, height: 52)
      }

      VStack(alignment: .leading, spacing: 3) {
        if !isCompact {
          Text(isFinished ? "What a trip!" : "City Scout")
            .font(.caption.weight(.bold))
            .foregroundStyle(CityChainPalette.teal)
        }
        Text(message)
          .font(.subheadline)
          .foregroundStyle(CityChainPalette.ink)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.updatesFrequently)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.leading, isCompact ? 12 : 4)
    .padding(.vertical, 12)
    .accessibilityElement(children: .combine)
  }
}

#Preview("Dismissible route feedback") {
  CityTurnFeedbackView(
    message: "Great job with Atlanta! I picked Albany from my atlas.",
    presentation: ScoutPresentation(), isFinished: false, onDismiss: {})
    .padding(20)
    .background(CityChainPalette.paper)
}

#Preview("Compact input error") {
  CityTurnFeedbackView(
    message: "We already visited Atlanta. Pick another!",
    presentation: ScoutPresentation(), isFinished: false,
    maximumHeight: 100, onDismiss: {})
    .padding(20)
    .background(CityChainPalette.paper)
}
