import SwiftUI

/// Decorative companion; the adjacent game message supplies accessible feedback.
struct ScoutView: View {
  let presentation: ScoutPresentation
  var style: ScoutViewStyle = .reaction
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    let reaction = ScoutReaction(pose: presentation.pose)
    let isSceneActive = scenePhase == .active
    if reduceMotion {
      ScoutSprite(pose: presentation.pose, style: style)
        .padding(style == .cornerCompanion ? 0 : 10)
    } else {
      ScoutSprite(pose: presentation.pose, style: style)
        .modifier(ScoutIdleMotion())
        .keyframeAnimator(
          initialValue: ScoutMotion(), trigger: presentation.reactionID
        ) { content, motion in
          content
            .scaleEffect(isSceneActive ? motion.scale : 1, anchor: .bottom)
            .rotationEffect(.degrees(isSceneActive ? motion.rotation : 0), anchor: .bottom)
            .offset(y: isSceneActive ? motion.height : 0)
        } keyframes: { _ in
          KeyframeTrack(\.height) {
            CubicKeyframe(reaction.lift, duration: 0.24)
            CubicKeyframe(0, duration: 0.36)
          }
          KeyframeTrack(\.scale) {
            CubicKeyframe(reaction.scale, duration: 0.24)
            CubicKeyframe(1, duration: 0.36)
          }
          KeyframeTrack(\.rotation) {
            CubicKeyframe(-reaction.tilt, duration: reaction.isCorrective ? 0.35 : 0.20)
            // Hold the questioning tilt long enough to read the expression.
            LinearKeyframe(-reaction.tilt, duration: reaction.isCorrective ? 0.70 : 0.08)
            CubicKeyframe(reaction.tilt, duration: reaction.isCorrective ? 0.40 : 0.24)
            CubicKeyframe(-reaction.tilt * 0.35, duration: reaction.isCorrective ? 0.25 : 0.18)
            CubicKeyframe(0, duration: reaction.isCorrective ? 0.30 : 0.18)
          }
        }
        .padding(style == .cornerCompanion ? 0 : 10)
    }
  }
}

enum ScoutViewStyle: Equatable {
  case reaction
  case cornerCompanion
}

private struct ScoutIdleMotion: ViewModifier {
  @Environment(\.scenePhase) private var scenePhase
  @State private var isVisible = true

  func body(content: Content) -> some View {
    Group {
      if scenePhase == .active && isVisible {
        content.phaseAnimator([false, true]) { sprite, breath in
          sprite
            .scaleEffect(breath ? 1.018 : 1, anchor: .bottom)
            .rotationEffect(.degrees(breath ? 1 : -1), anchor: .bottom)
            .offset(y: breath ? -1 : 0)
        } animation: { _ in
          .easeInOut(duration: 2.8)
        }
      } else {
        content
      }
    }
    .onGeometryChange(for: Bool.self) { geometry in
      guard let viewport = geometry.bounds(of: .scrollView(axis: .vertical)) else {
        return true
      }
      return viewport.intersects(CGRect(origin: .zero, size: geometry.size))
    } action: { isVisible = $0 }
  }
}

private struct ScoutReaction {
  let lift: CGFloat
  let scale: CGFloat
  let tilt: Double
  let isCorrective: Bool

  init(pose: ScoutPose) {
    isCorrective = pose == .tryAnother
    switch pose {
    case .welcome:
      (lift, scale, tilt) = (-4, 1.02, 8)
    case .thinking:
      (lift, scale, tilt) = (0, 1, 3)
    case .celebration:
      (lift, scale, tilt) = (-12, 1.05, 6)
    case .tryAnother:
      (lift, scale, tilt) = (0, 1, 7)
    }
  }
}

private struct ScoutMotion {
  var height: CGFloat = 0
  var scale: CGFloat = 1
  var rotation: Double = 0
}

/// Link to the source of a Scout fact, shared by feedback and atlas surfaces.
struct ScoutFactSourceLink: View {
  let fact: ScoutFact
  var font: Font = .caption.weight(.semibold)

  var body: some View {
    Link(destination: fact.sourceURL) {
      Label("Fact source", systemImage: "arrow.up.right.square")
        .font(font)
    }
    .tint(CityChainPalette.teal)
    .accessibilityLabel("Fact source")
    .accessibilityHint("Opens \(fact.sourceTitle)")
  }
}

private struct ScoutSprite: View {
  let pose: ScoutPose
  let style: ScoutViewStyle
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Image(assetName)
        .resizable()
        .scaledToFit()
        .id(assetName)
        .transition(.opacity)
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: assetName)
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  private var assetName: String {
    pose == .welcome ? "ScoutThinking" : pose.assetName
  }
}

struct ScoutAvatar: View {
  var body: some View {
    Image("ScoutAvatar")
      .resizable()
      .scaledToFit()
      .accessibilityHidden(true)
      .allowsHitTesting(false)
  }
}

#Preview("Scout reactions") {
  ScoutReactionPreview()
}

private struct ScoutReactionPreview: View {
  @State private var pose = ScoutPose.welcome
  @State private var reactionID: UInt64 = 0

  private var presentation: ScoutPresentation {
    ScoutPresentation(pose: pose, reactionID: reactionID)
  }

  var body: some View {
    VStack(spacing: 20) {
      ScoutView(presentation: presentation)
        .frame(width: 240, height: 240)
      ForEach(ScoutPose.allCases, id: \.self) { pose in
        Button(pose.rawValue) {
          self.pose = pose
          reactionID &+= 1
        }
      }
      ScoutAvatar()
        .frame(width: 48, height: 48)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CityChainPalette.paper)
    .onAppear { reactionID &+= 1 }
  }
}
