import Foundation
import SwiftUI
import OracleGame

struct OraclePage: View {
  @State private var model: OraclePageModel
  @State private var isShowingInfo = false

  init(model: OraclePageModel = OraclePageModel()) {
    _model = State(initialValue: model)
  }

  var body: some View {
    GeometryReader { proxy in
      let availableHeight = max(proxy.size.height, 1)
      let viewportSide = max(1, min(proxy.size.width - 16, max(180, availableHeight - 260)))

      ZStack {
        OracleCosmicBackground()

        ScrollView {
          VStack(spacing: 0) {
            OracleHeader { isShowingInfo = true }
              .padding(.top, 10)

            Spacer(minLength: 4)

            ZStack(alignment: .bottom) {
              Ellipse()
                .fill(Color.oraclePurple.opacity(0.25))
                .frame(width: viewportSide * 0.9, height: viewportSide * 0.16)
                .blur(radius: viewportSide * 0.08)
                .offset(y: -viewportSide * 0.03)
                .accessibilityHidden(true)

              Ellipse()
                .stroke(Color.oracleLavender.opacity(0.7), lineWidth: 1)
                .frame(width: viewportSide * 0.72, height: viewportSide * 0.085)
                .shadow(color: .oraclePurple, radius: 7)
                .offset(y: -viewportSide * 0.058)
                .accessibilityHidden(true)

              OracleBallViewport(
                answer: model.answer.displayText,
                requestID: model.requestID,
                answerRequestID: model.answerRequestID,
                terminalRequestID: model.terminalRequestID)
                .frame(width: viewportSide, height: viewportSide)
                .id("oracle-ball-viewport")
                .accessibilityLabel(
                  "Oracle answer: \(model.answer.displayText.replacingOccurrences(of: "\n", with: " "))")
            }
            .frame(width: viewportSide, height: viewportSide)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 4)

            VStack(spacing: 12) {
              AskOracleField(text: $model.question, onSubmit: model.submit)
              OracleModeSelector(selection: $model.mode)
              Text(model.statusMessage ?? model.providerDescription)
                .font(.caption2.weight(.medium))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.34))
                .multilineTextAlignment(.center)
                .accessibilityLabel(model.statusMessage ?? model.providerDescription)
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)

            Text("AI MAGIC 8-BALL  ·  ASK WITH INTENT")
              .font(.system(size: 9, weight: .medium, design: .rounded))
              .tracking(1.4)
              .foregroundStyle(.white.opacity(0.3))
              .padding(.top, 12)
              .padding(.bottom, 8)
          }
          .frame(minHeight: availableHeight)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
      }
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: $isShowingInfo) {
      OracleInfoSheet(
        apiKey: model.configuredAPIKey,
        providerDescription: model.providerDescription,
        onSave: model.saveAPIKey)
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
    }
  }

}

private struct OracleHeader: View {
  let onInfo: () -> Void

  var body: some View {
    HStack {
      OracleSpark()
        .fill(.white.opacity(0.9))
        .frame(width: 16, height: 16)
        .shadow(color: .oracleLavender.opacity(0.8), radius: 8)
        .accessibilityHidden(true)

      Text("A I   M A G I C   8 - B A L L")
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .tracking(1.2)
        .foregroundStyle(.white.opacity(0.66))

      Spacer()

      Button(action: onInfo) {
        Image(systemName: "info.circle")
          .font(.body.weight(.medium))
          .foregroundStyle(.white.opacity(0.55))
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Oracle settings")
    }
    .padding(.horizontal, 16)
  }
}

private struct OracleSpark: Shape {
  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let outerX = rect.width / 2
    let outerY = rect.height / 2
    let innerX = rect.width * 0.14
    let innerY = rect.height * 0.14
    let points = [
      CGPoint(x: center.x, y: center.y - outerY),
      CGPoint(x: center.x + innerX, y: center.y - innerY),
      CGPoint(x: center.x + outerX, y: center.y),
      CGPoint(x: center.x + innerX, y: center.y + innerY),
      CGPoint(x: center.x, y: center.y + outerY),
      CGPoint(x: center.x - innerX, y: center.y + innerY),
      CGPoint(x: center.x - outerX, y: center.y),
      CGPoint(x: center.x - innerX, y: center.y - innerY),
    ]
    var path = Path()
    path.move(to: points[0])
    for point in points.dropFirst() { path.addLine(to: point) }
    path.closeSubpath()
    return path
  }
}

private struct OracleInfoSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var apiKey: String
  @State private var isConfigured: Bool

  let providerDescription: String
  let onSave: (String) -> Bool

  init(apiKey: String, providerDescription: String, onSave: @escaping (String) -> Bool) {
    _apiKey = State(initialValue: apiKey)
    _isConfigured = State(initialValue: !apiKey.isEmpty)
    self.providerDescription = providerDescription
    self.onSave = onSave
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Oracle settings")
          .font(.title3.weight(.semibold))
        Spacer()
        Image(systemName: "lock.shield")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }

      Text("TypeSafe Jev")
        .font(.headline)
      Text(
        "Add a TypeSafe.ai API key to ask Jev for structured Noul, Choice, and Score answers. The key is stored securely in this device's Keychain."
      )
      .font(.subheadline)
      .foregroundStyle(.secondary)

      Link(destination: URL(string: "https://typesafe.ai")!) {
        Label("Learn more at TypeSafe.ai", systemImage: "arrow.up.right.square")
          .font(.subheadline.weight(.medium))
      }

      HStack(spacing: 10) {
        Image(systemName: "key.fill")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        SecureField("TYPESAFE_API_KEY", text: $apiKey)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.asciiCapable)
          .textFieldStyle(.plain)
          .accessibilityLabel("TypeSafe API key")
      }
      .padding(.horizontal, 16)
      .frame(minHeight: 48)
      .background(.white.opacity(0.08), in: Capsule())
      .overlay {
        Capsule()
          .stroke(.white.opacity(0.18), lineWidth: 1)
      }

      Label(
        isConfigured ? "Jev key configured" : "Offline fixture active",
        systemImage: isConfigured ? "checkmark.circle.fill" : "circle.dashed")
        .font(.caption)
        .foregroundStyle(isConfigured ? .green : .secondary)

      Text(providerDescription)
        .font(.caption2)
        .foregroundStyle(.secondary)

      HStack {
        Button("Clear key") {
          apiKey = ""
          if onSave("") {
            isConfigured = false
            dismiss()
          }
        }
        .buttonStyle(.bordered)

        Spacer()

        Button("Save") {
          if onSave(apiKey) {
            isConfigured = true
            dismiss()
          }
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(24)
  }
}

#Preview {
  OraclePage()
}
