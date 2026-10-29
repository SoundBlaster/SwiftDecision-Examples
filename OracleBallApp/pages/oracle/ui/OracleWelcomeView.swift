import SwiftUI
import OraclePresentation

/// A short first-run introduction. Age confirmation is self-declared, not verification.
struct OracleWelcomeView: View {
  let model: OraclePageModel
  let onFinish: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var page: Page = .welcome
  @State private var showsUnderageNotice = false

  private enum Page: Int {
    case welcome, age, model
  }

  var body: some View {
    GeometryReader { geometry in
      let compact = OracleWelcomeCompactLayoutSpec().isSatisfiedBy(Double(geometry.size.height))
      if let fold = foldFrames(in: geometry) {
        foldLayout(fold)
      } else {
        regularLayout(compact: compact)
      }
    }
    .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    .tint(.purple)
    .alert("For adults only", isPresented: $showsUnderageNotice) {
      Button("OK", role: .cancel) { }
    } message: {
      Text("This app is intended for people who are 18 or older.")
    }
    .accessibilityIdentifier("oracle.welcome")
  }

  private func regularLayout(compact: Bool) -> some View {
    ScrollView {
      VStack(spacing: compact ? 14 : (page == .welcome ? 32 : 28)) {
        pageHeader(compact: compact)
        pageContent(compact: compact)
      }
      .frame(maxWidth: 460)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 28)
      .padding(.top, compact ? 24 : 90)
      .padding(.bottom, compact ? 12 : 24)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) { footer }
  }

  private var footer: some View {
    controls
      .frame(maxWidth: 460)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 28)
      .padding(.top, 14)
      .padding(.bottom, 12)
      .background(Color(uiColor: .systemGroupedBackground))
  }

  @ViewBuilder private func pageHeader(compact: Bool) -> some View {
    switch page {
    case .welcome:
      welcomeHeader(symbol: "sparkles", title: "Welcome to\nEndless Answers",
                    subtitle: "A little wonder for the\nquestions on your mind.", compact: compact)
    case .age:
      welcomeHeader(symbol: "person.crop.circle.badge.checkmark", title: "For adults\n18 and over",
                    subtitle: "Endless Answers is intended\nfor adults.", compact: compact)
    case .model:
      welcomeHeader(symbol: "arrow.down.circle.fill", title: "AI on\nyour device",
                    subtitle: "Download GLiNER small to explore\nquestions on your device.", compact: compact)
    }
  }

  @ViewBuilder private func pageContent(compact: Bool) -> some View {
    switch page {
    case .welcome:
      VStack(alignment: .leading, spacing: compact ? 12 : 28) {
        feature(symbol: "dice.fill", title: "Random game",
                description: "Shake the ball or tap send without a question for a random answer.")
        feature(symbol: "brain", title: "On-device AI",
                description: "Ask a question and explore an answer with an optional local model.")
        feature(symbol: "hand.raised.fill", title: "For entertainment",
                description: "Answers are not advice. Make important decisions with care.")
      }
    case .age:
      Text("This is an entertainment app. Do not rely on its answers for decisions about safety, health, or other important matters.")
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    case .model:
      VStack(spacing: compact ? 14 : 28) {
        VStack(alignment: .leading, spacing: compact ? 12 : 24) {
          feature(symbol: "iphone", title: "Private by design",
                  description: "With GLiNER, questions are processed on this device.\nNo internet is needed after installation.")
          feature(symbol: "internaldrive", title: "Optional download",
                  description: "About 70 MB to download and 87 MB of storage. You can install or remove it later in Settings.")
          feature(symbol: "text.bubble", title: "Experimental English model",
                  description: "Results can be uncertain or incorrect.")
        }
        if model.isDownloadingModel || model.isPreparingModel {
          downloadProgress
        } else if model.isModelInstalled {
          Label("Local model installed", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }
        if let issue = model.modelIssue {
          Text(issue).font(.footnote).foregroundStyle(.orange)
            .multilineTextAlignment(.center)
        }
      }
    }
  }

  private struct FoldFrames {
    let before: CGRect
    let after: CGRect
    let plan: OracleWelcomeFoldPlan
  }

  private func foldFrames(in geometry: GeometryProxy) -> FoldFrames? {
    #if ORACLE_HAS_RESERVED_REGIONS
    if #available(iOS 27.1, *) {
      let bounds = CGRect(origin: .zero, size: geometry.size)
      guard let region = geometry.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
        .first(where: { $0.isActive && $0.frame.intersects(bounds) }) else { return nil }
      let fold = region.frame.intersection(bounds)
      guard !fold.isEmpty else { return nil }
      let vertical = fold.height >= fold.width
      let before = CGRect(x: 0, y: 0, width: vertical ? fold.minX : bounds.width,
                          height: vertical ? bounds.height : fold.minY)
      let after = CGRect(x: vertical ? fold.maxX : 0, y: vertical ? 0 : fold.maxY,
                         width: vertical ? max(0, bounds.width - fold.maxX) : bounds.width,
                         height: vertical ? bounds.height : max(0, bounds.height - fold.maxY))
      let context = OracleWelcomeFoldContext(
        before: .init(width: before.width, height: before.height),
        after: .init(width: after.width, height: after.height))
      guard let plan = OracleWelcomeFoldLayoutSpec().decide(context) else { return nil }
      return FoldFrames(before: before, after: after, plan: plan)
    }
    #endif
    return nil
  }

  @ViewBuilder private func foldLayout(_ fold: FoldFrames) -> some View {
    ZStack(alignment: .topLeading) {
      if fold.plan == .split {
        ScrollView {
          pageHeader(compact: true)
            .frame(maxWidth: .infinity, minHeight: max(0, fold.before.height - 32))
            .padding(16)
        }
        .frame(width: fold.before.width, height: fold.before.height)
        .clipped()
        .position(x: fold.before.midX, y: fold.before.midY)

        ScrollView {
          pageContent(compact: true)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .frame(width: fold.after.width, height: fold.after.height)
        .clipped()
        .position(x: fold.after.midX, y: fold.after.midY)
      } else {
        let frame = fold.plan == .before ? fold.before : fold.after
        regularLayout(compact: true)
          .frame(width: frame.width, height: frame.height)
          .clipped()
          .position(x: frame.midX, y: frame.midY)
      }
    }
  }

  private var downloadProgress: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(systemName: model.isDownloadingModel ? "arrow.down.circle" : "gearshape")
          .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
          .accessibilityHidden(true)
        if model.isDownloadingModel {
          if model.modelDownloadProgress == nil {
            Text("Connecting…")
          } else {
            Text("Downloading…")
          }
        } else {
          Text("Preparing model…")
        }
        Spacer()
        if model.isDownloadingModel, let progress = model.modelDownloadProgress {
          Text(progress, format: .percent.precision(.fractionLength(0)))
            .monospacedDigit().foregroundStyle(.secondary)
        }
      }
      ProgressView(value: model.modelDownloadProgress ?? 0)
    }
    .accessibilityElement(children: .combine)
  }

  private var controls: some View {
    VStack(spacing: 14) {
      switch page {
      case .welcome:
        primaryButton("Continue") { page = .age }
          .accessibilityIdentifier("oracle.welcome.continue")
      case .age:
        primaryButton("I am 18 or older") { page = .model }
          .accessibilityIdentifier("oracle.welcome.confirm-age")
        Button("I am under 18") { showsUnderageNotice = true }
          .accessibilityIdentifier("oracle.welcome.underage")
      case .model:
        if model.isDownloadingModel || model.isPreparingModel {
          primaryButton("Continue while preparing", action: onFinish)
          if model.isDownloadingModel {
            Button("Cancel download", action: model.cancelHostedModelInstallation)
          }
        } else if model.isModelInstalled {
          primaryButton("Continue", action: onFinish)
            .accessibilityIdentifier("oracle.welcome.installed-continue")
        } else if model.supportsGLiNER {
          primaryButton(model.modelIssue == nil ? "Download model" : "Try again",
                        action: model.installHostedGLiNERModel)
          Button("Not now", action: onFinish)
            .accessibilityIdentifier("oracle.welcome.skip-model")
        } else {
          primaryButton("Continue", action: onFinish)
        }
      }
    }
    .font(.body.weight(.semibold))
  }

  private func primaryButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).frame(maxWidth: .infinity).frame(minHeight: 50)
    }
    .buttonStyle(OracleWelcomeButtonStyle())
  }

  private func welcomeHeader(symbol: String, title: LocalizedStringKey,
                             subtitle: LocalizedStringKey, compact: Bool) -> some View {
    VStack(spacing: compact ? 10 : 16) {
      Image(systemName: symbol)
        .font(.system(size: 96, weight: .medium))
        .foregroundStyle(oracleWelcomeGradient)
        .accessibilityHidden(true)
      Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
      Text(subtitle).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }
  }

  private func feature(symbol: String, title: LocalizedStringKey,
                       description: LocalizedStringKey) -> some View {
    HStack(alignment: .top, spacing: 18) {
      Image(systemName: symbol)
        .font(.title2.weight(.semibold))
        .foregroundStyle(oracleWelcomeGradient)
        .frame(width: 36)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.headline)
        Text(description).font(.subheadline).foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

private let oracleWelcomeGradient = LinearGradient(
  colors: [Color(red: 0.91, green: 0.20, blue: 0.91), Color(red: 0.69, green: 0.16, blue: 0.91)],
  startPoint: .topLeading,
  endPoint: .bottomTrailing)

private struct OracleWelcomeButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.white)
      .background(oracleWelcomeGradient, in: RoundedRectangle(cornerRadius: 16))
      .opacity(configuration.isPressed ? 0.75 : 1)
  }
}
