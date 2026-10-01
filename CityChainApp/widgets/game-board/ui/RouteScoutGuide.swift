import CityChainGame
import SwiftUI

/// Scout standing on a rock in the corner of the route card, sharing the same facts
/// and status lines as the header companion. A pure overlay: the route card keeps
/// its own layout, and only the speech bubble takes touches.
/// Closing the bubble goes through the same dismissal as the header, so Scout's
/// state machine moves on and both bubbles stay in sync.
struct RouteScoutGuide: View {
  let message: String?
  let fact: ScoutFact?
  let presentation: ScoutPresentation
  var onTapScout: (() -> Void)? = nil
  var canDismiss = false
  var onDismiss: () -> Void = {}
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Pixel size of the cropped `ScoutRock` artwork.
  private static let rockAspect: CGFloat = 499.0 / 900.0

  var body: some View {
    GeometryReader { geometry in
      let size = geometry.size
      let scoutSide = size.height * 0.52
      let rockWidth = scoutSide * 1.2
      let rockHeight = rockWidth * Self.rockAspect
      // Tucked into the corner: the bushes spill past the card's left edge and rounded
      // corner, while the rock is cut flush with the card's bottom line.
      let rockOrigin = CGPoint(x: -rockWidth * 0.1, y: size.height - rockHeight * 0.74)
      // Planted on the stone just left of its crown.
      let feet = CGPoint(x: rockOrigin.x + rockWidth * 0.45, y: rockOrigin.y + rockHeight * 0.66)
      let scoutOrigin = CGPoint(x: feet.x - scoutSide / 2, y: feet.y - scoutSide * 0.94)
      // Anchored to the rock rather than to Scout, so nudging Scout keeps the bubble's width.
      let bubbleLeading = rockOrigin.x + rockWidth * 0.4 + scoutSide * 0.32
      // Grows upwards from above the "Next" caption, stopping short of the start stop.
      let bubbleTop = size.height * 0.34
      let bubbleBottom = size.height * 0.84

      ZStack(alignment: .topLeading) {
        Image("ScoutRock")
          .resizable()
          .frame(width: rockWidth, height: rockHeight)
          .offset(x: rockOrigin.x, y: rockOrigin.y)
          .accessibilityHidden(true)
          .allowsHitTesting(false)

        Group {
          if let onTapScout {
            Button(action: onTapScout) {
              ScoutView(presentation: presentation, style: .cornerCompanion)
                .frame(width: scoutSide, height: scoutSide)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open atlas map")
            .accessibilityHint("Shows the map of your road trip")
            .accessibilityIdentifier("cityChain.scout.openMap")
          } else {
            ScoutView(presentation: presentation, style: .cornerCompanion)
              .frame(width: scoutSide, height: scoutSide)
              .accessibilityHidden(true)
          }
        }
        .frame(width: scoutSide, height: scoutSide)
        .offset(x: scoutOrigin.x, y: scoutOrigin.y)

        if let speech {
          RouteScoutBubble(
            title: speech.title, text: speech.text, fact: fact,
            onDismiss: canDismiss ? onDismiss : nil)
            .frame(
              width: min(size.width * 0.76 - bubbleLeading, 300),
              height: bubbleBottom - bubbleTop)
            .offset(x: bubbleLeading, y: bubbleTop)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
        }
      }
      .frame(width: size.width, height: size.height, alignment: .topLeading)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: speech?.text)
    }
    // Clips only below the card; the other sides stay open for the spilling bushes.
    .mask {
      Rectangle()
        .padding(.horizontal, -80)
        .padding(.top, -80)
    }
  }

  /// A fact wins over the status line: the header already carries the full message.
  private var speech: (title: LocalizedStringKey?, text: String)? {
    if let fact { return ("Fun fact!", fact.text) }
    if let message { return (nil, message) }
    return nil
  }
}

/// Comic bubble whose tail points left at Scout; scrolls when the text outgrows the card.
private struct RouteScoutBubble: View {
  let title: LocalizedStringKey?
  let text: String
  let fact: ScoutFact?
  let onDismiss: (() -> Void)?

  /// Keeps the first line clear of the close badge sitting on the corner.
  private var badgeClearance: CGFloat { onDismiss == nil ? 0 : 14 }

  var body: some View {
    bubble(
      VStack(alignment: .leading, spacing: 3) {
        // Only the words scroll; the source link stays reachable at the bottom.
        ViewThatFits(in: .vertical) {
          words
          ScrollView { words }.scrollBounceBehavior(.basedOnSize)
        }
        if let fact {
          Link(destination: fact.sourceURL) {
            Label("Fact source", systemImage: "arrow.up.right.square")
              .font(.caption.weight(.semibold))
          }
          .tint(CityChainPalette.teal)
          .accessibilityHint("Opens \(fact.sourceTitle)")
        }
      })
    .overlay(alignment: .topTrailing) {
      if let onDismiss {
        Button(action: onDismiss) {
          Image(systemName: "xmark")
            .font(.caption2.weight(.bold))
            .foregroundStyle(CityChainPalette.secondaryInk)
            .frame(width: 24, height: 24)
            .background(.white, in: Circle())
            .overlay { Circle().strokeBorder(CityChainPalette.ink.opacity(0.11), lineWidth: 1) }
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: 18, y: -18)
        .accessibilityLabel("Dismiss message")
      }
    }
    .frame(maxHeight: .infinity, alignment: .bottom)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .accessibilityElement(children: .contain)
    .modifier(DismissAction(onDismiss: onDismiss))
  }

  private var words: some View {
    VStack(alignment: .leading, spacing: 3) {
      if let title {
        Text(title)
          .font(.system(.subheadline, design: .rounded, weight: .heavy))
          .foregroundStyle(CityChainPalette.ink)
          .accessibilityAddTraits(.isHeader)
          .padding(.trailing, badgeClearance)
      }
      Text(text)
        .font(.footnote)
        .foregroundStyle(CityChainPalette.ink)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.trailing, title == nil ? badgeClearance : 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func bubble(_ content: some View) -> some View {
    content
      .padding(.leading, RouteScoutBubbleShape.tailWidth + 10)
      .padding(.trailing, 10)
      .padding(.vertical, 8)
      .background {
        RouteScoutBubbleShape()
          .fill(Color(red: 1, green: 0.985, blue: 0.94))
          .shadow(color: .black.opacity(0.06), radius: 7, y: 3)
      }
      .overlay {
        RouteScoutBubbleShape()
          .stroke(CityChainPalette.ink.opacity(0.11), lineWidth: 1)
          .accessibilityHidden(true)
      }
  }
}

private struct DismissAction: ViewModifier {
  let onDismiss: (() -> Void)?

  func body(content: Content) -> some View {
    if let onDismiss {
      content.accessibilityAction(named: "Dismiss message", onDismiss)
    } else {
      content
    }
  }
}

private struct RouteScoutBubbleShape: Shape {
  static let tailWidth: CGFloat = 14

  func path(in rect: CGRect) -> Path {
    Path { path in
      let radius = min(18, rect.height * 0.3)
      let left = rect.minX + Self.tailWidth
      // The tail must fit on the straight edge between the two left corners, or the
      // outline doubles back on itself (visible on one-line bubbles).
      let straightEdge = rect.height - radius * 2
      let tailHalfHeight = min(10, max(straightEdge / 2, 0))
      let tailCenter = min(
        max(rect.minY + min(rect.height * 0.42, 56), rect.minY + radius + tailHalfHeight),
        rect.maxY - radius - tailHalfHeight)

      path.move(to: CGPoint(x: left + radius, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
      path.addQuadCurve(
        to: CGPoint(x: rect.maxX, y: rect.minY + radius),
        control: CGPoint(x: rect.maxX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
      path.addQuadCurve(
        to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
        control: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: left + radius, y: rect.maxY))
      path.addQuadCurve(
        to: CGPoint(x: left, y: rect.maxY - radius),
        control: CGPoint(x: left, y: rect.maxY))
      path.addLine(to: CGPoint(x: left, y: tailCenter + tailHalfHeight))
      path.addQuadCurve(
        to: CGPoint(x: rect.minX, y: tailCenter),
        control: CGPoint(x: left - Self.tailWidth * 0.4, y: tailCenter + 6))
      path.addQuadCurve(
        to: CGPoint(x: left, y: tailCenter - tailHalfHeight),
        control: CGPoint(x: left - Self.tailWidth * 0.55, y: tailCenter - tailHalfHeight))
      path.addLine(to: CGPoint(x: left, y: rect.minY + radius))
      path.addQuadCurve(
        to: CGPoint(x: left + radius, y: rect.minY),
        control: CGPoint(x: left, y: rect.minY))
      path.closeSubpath()
    }
  }
}

#Preview("Route Scout — fun fact", traits: .sizeThatFitsLayout) {
  RouteScoutGuidePreview(
    message: nil,
    fact: RouteScoutGuidePreview.fact(
      "Ogden grew into a major railroad hub in the American West."),
    canDismiss: true)
}

#Preview("Route Scout — status", traits: .sizeThatFitsLayout) {
  RouteScoutGuidePreview(message: "One moment, I'm thinking!", fact: nil)
}

#Preview("Route Scout — one line", traits: .sizeThatFitsLayout) {
  // The shortest bubble: the tail must still sit between the rounded corners.
  RouteScoutGuidePreview(message: "Hmm, let me look!", fact: nil)
}

#Preview("Route Scout — idle", traits: .sizeThatFitsLayout) {
  RouteScoutGuidePreview(message: nil, fact: nil)
}

#Preview("Route Scout — long fact", traits: .sizeThatFitsLayout) {
  RouteScoutGuidePreview(
    message: nil,
    fact: RouteScoutGuidePreview.fact(
      "Pennsylvania's highest point is Mount Davis, a gentle summit in the Laurel Highlands "
        + "that rises 3,213 feet above sea level and has an observation tower on top."))
}

private struct RouteScoutGuidePreview: View {
  let message: String?
  @State var fact: ScoutFact?
  var canDismiss = false
  @State var presentation = ScoutPresentation(pose: .celebration, reactionID: 1)

  var body: some View {
    ScenicRouteJourneyCard(
      cities: [USCity("Ogden", state: .utah)], isWaitingForScout: false)
      .overlay {
        RouteScoutGuide(
          message: message, fact: fact, presentation: presentation,
          canDismiss: canDismiss && fact != nil,
          onDismiss: {
            // Mirrors the page: the fact clears and Scout returns to idle.
            fact = nil
            presentation = ScoutPresentation(pose: .welcome, reactionID: presentation.reactionID &+ 1)
          })
      }
      .frame(width: 350)
      .padding(20)
      .background(CityChainPalette.paper)
  }

  static func fact(_ text: String) -> ScoutFact {
    let json = """
      {"id": "preview", "text": "\(text)", "sourceTitle": "Preview source",
       "sourceURL": "https://example.com"}
      """
    return try! JSONDecoder().decode(ScoutFact.self, from: Data(json.utf8))
  }
}
