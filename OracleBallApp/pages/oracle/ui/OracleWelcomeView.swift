import SwiftUI

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
    ScrollView {
      VStack(spacing: 32) {
        switch page {
        case .welcome: welcomeContent
        case .age: ageContent
        case .model: modelContent
        }
      }
      .frame(maxWidth: 460)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 28)
      .padding(.top, 50)
      .padding(.bottom, 24)
    }
    .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    .safeAreaInset(edge: .bottom, spacing: 0) {
      controls
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }
    .tint(.purple)
    .alert("For adults only", isPresented: $showsUnderageNotice) {
      Button("OK", role: .cancel) { }
    } message: {
      Text("This app is intended for people who are 18 or older.")
    }
    .accessibilityIdentifier("oracle.welcome")
  }

  private var welcomeContent: some View {
    VStack(spacing: 32) {
      welcomeHeader(symbol: "sparkles", title: "Welcome to Endless Answers",
                    subtitle: "A little wonder for the questions on your mind.")
      VStack(alignment: .leading, spacing: 28) {
        feature(symbol: "dice.fill", title: "Random game",
                description: "Shake the ball or tap send without a question for a random answer.")
        feature(symbol: "brain", title: "On-device AI",
                description: "Ask a question and explore an answer with an optional local model.")
        feature(symbol: "hand.raised.fill", title: "For entertainment",
                description: "Answers are not advice. Make important decisions with care.")
      }
    }
  }

  private var ageContent: some View {
    VStack(spacing: 28) {
      welcomeHeader(symbol: "person.crop.circle.badge.checkmark", title: "For adults, 18 and over",
                    subtitle: "Endless Answers is intended for adults.")
      Text("This is an entertainment app. Do not rely on its answers for decisions about safety, health, or other important matters.")
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
  }

  private var modelContent: some View {
    VStack(spacing: 28) {
      welcomeHeader(symbol: "arrow.down.circle.fill", title: "On-device AI",
                    subtitle: "Download GLiNER small to explore questions on your device.")
      VStack(alignment: .leading, spacing: 24) {
        feature(symbol: "iphone", title: "Private by design",
                description: "When using GLiNER, questions are processed on this device.")
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
      HStack(spacing: 7) {
        ForEach(0..<3) { index in
          Circle().fill(index == page.rawValue ? Color.primary : Color.secondary.opacity(0.35))
            .frame(width: 7, height: 7)
        }
      }
      .accessibilityLabel("Step \(page.rawValue + 1) of 3")

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
      Text(title).frame(maxWidth: .infinity).padding(.vertical, 10)
    }
    .buttonStyle(.borderedProminent)
    .buttonBorderShape(.roundedRectangle(radius: 16))
  }

  private func welcomeHeader(symbol: String, title: LocalizedStringKey,
                             subtitle: LocalizedStringKey) -> some View {
    VStack(spacing: 16) {
      Image(systemName: symbol)
        .font(.system(size: 48, weight: .medium))
        .foregroundStyle(.tint)
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
        .foregroundStyle(.tint)
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
