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

/// Scout speaks beside a comic-style bubble without a card behind the sprite.
struct ScoutSpeechFeedbackView: View {
  let message: String?
  let presentation: ScoutPresentation
  let isCompact: Bool
  let onDismiss: () -> Void
  var companionSize: CGFloat? = nil
  var horizontalPadding: CGFloat = 16
  var bubbleBottomInset: CGFloat = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(alignment: .bottom, spacing: -18) {
      if let message {
        HStack(alignment: .top, spacing: 4) {
          Text(message)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(CityChainPalette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.updatesFrequently)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)

          Button(action: onDismiss) {
            Image(systemName: "xmark")
              .font(.caption.weight(.semibold))
              .foregroundStyle(CityChainPalette.secondaryInk)
              .frame(width: 44, height: 44)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Dismiss message")
        }
        .padding(.leading, 18)
        .padding(.trailing, 28)
        .padding(.vertical, 8)
        .background {
          ScoutSpeechBubbleShape()
            .fill(Color(red: 1, green: 0.985, blue: 0.94))
            .shadow(color: .black.opacity(0.055), radius: 7, y: 3)
            .allowsHitTesting(false)
        }
        .overlay {
          ScoutSpeechBubbleShape()
            .stroke(CityChainPalette.ink.opacity(0.11), lineWidth: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .trailing)))
        .offset(y: -bubbleBottomInset)
      }

      ScoutView(presentation: presentation, style: .cornerCompanion)
        .frame(
          width: companionSize ?? (isCompact ? 108 : 176),
          height: companionSize ?? (isCompact ? 112 : 180))
        .accessibilityHidden(true)
    }
    .padding(.horizontal, horizontalPadding)
    .padding(.top, message == nil ? 0 : 8)
    .padding(.bottom, 2)
    .frame(maxWidth: .infinity, alignment: .trailing)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: message)
    .accessibilityElement(children: message == nil ? .ignore : .contain)
    .accessibilityHidden(message == nil)
    .accessibilityAction(named: "Dismiss message", onDismiss)
  }
}

private struct ScoutSpeechBubbleShape: Shape {
  func path(in rect: CGRect) -> Path {
    Path { path in
      let radius = min(22, rect.height * 0.22)
      let tailWidth: CGFloat = 22
      let bodyRight = rect.maxX - tailWidth
      let tailCenter = rect.minY + rect.height * 0.43
      let tailHalfHeight: CGFloat = 12

      path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
      path.addLine(to: CGPoint(x: bodyRight - radius, y: rect.minY))
      path.addQuadCurve(
        to: CGPoint(x: bodyRight, y: rect.minY + radius),
        control: CGPoint(x: bodyRight, y: rect.minY))
      path.addLine(to: CGPoint(x: bodyRight, y: tailCenter - tailHalfHeight))
      path.addQuadCurve(
        to: CGPoint(x: rect.maxX, y: tailCenter),
        control: CGPoint(x: bodyRight + tailWidth * 0.55, y: tailCenter - tailHalfHeight))
      path.addQuadCurve(
        to: CGPoint(x: bodyRight, y: tailCenter + tailHalfHeight),
        control: CGPoint(x: rect.maxX - tailWidth * 0.38, y: tailCenter + 8))
      path.addLine(to: CGPoint(x: bodyRight, y: rect.maxY - radius))
      path.addQuadCurve(
        to: CGPoint(x: bodyRight - radius, y: rect.maxY),
        control: CGPoint(x: bodyRight, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
      path.addQuadCurve(
        to: CGPoint(x: rect.minX, y: rect.maxY - radius),
        control: CGPoint(x: rect.minX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
      path.addQuadCurve(
        to: CGPoint(x: rect.minX + radius, y: rect.minY),
        control: CGPoint(x: rect.minX, y: rect.minY))
      path.closeSubpath()
    }
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

#Preview("Scout speech bubble") {
  VStack {
    Spacer()
    ScoutSpeechFeedbackView(
      message: "Great job with Sacramento! I picked Olympia from my atlas.",
      presentation: ScoutPresentation(), isCompact: false, onDismiss: {})
  }
  .padding(.bottom, 16)
  .frame(maxWidth: .infinity, maxHeight: .infinity)
  .background(CityChainPalette.paper)
}

#Preview("Scout corner idle") {
  VStack(spacing: 12) {
    Spacer()
    ScoutSpeechFeedbackView(
      message: nil, presentation: ScoutPresentation(), isCompact: false, onDismiss: {})
  }
  .frame(maxWidth: .infinity, maxHeight: .infinity)
  .background(CityChainPalette.paper)
}
