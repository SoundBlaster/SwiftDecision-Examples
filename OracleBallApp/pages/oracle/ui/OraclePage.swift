import Foundation
import SwiftUI
import UIKit
import OracleGame
import OracleHistory
import NestedA11yIDs

struct OraclePage: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var model: OraclePageModel
  @State private var isShowingInfo = false
  @State private var infoSheetDetent: PresentationDetent = .medium
  @FocusState private var isQuestionFocused: Bool
  @State private var questionFieldFrame: CGRect = .zero
  @State private var ballViewportFrame: CGRect = .zero
  @State private var isKeyboardVisible = false
  @State private var bottomDescriptionHeight: CGFloat = 52
  @State private var initialBallViewportSide: CGFloat?

  init(model: OraclePageModel = OraclePageModel()) {
    _model = State(initialValue: model)
  }

  var body: some View {
    GeometryReader { proxy in
      let availableHeight = max(proxy.size.height, 1)
      let responsiveViewportSide = max(
        1, min(proxy.size.width - 16, max(180, availableHeight - 260)))
      let widthLimitedViewportSide = min(
        initialBallViewportSide ?? responsiveViewportSide,
        max(1, proxy.size.width - 16))
      // Keep the initial size while typing, but fit the current viewport when the
      // keyboard is hidden and the device layout changes (for example, on iPad rotation).
      let viewportSide = isKeyboardVisible
        ? widthLimitedViewportSide
        : min(widthLimitedViewportSide, max(1, availableHeight - 260))
      // The RealityKit scene has animated field rings below BallRoot; offset the viewport
      // slightly so the sphere itself, rather than the full scene bounds, reads as centered.
      let sceneCompositionOffset = viewportSide * 0.06

      ZStack {
        OracleCosmicBackground()

        OracleBallViewport(
          answer: model.answer.displayText,
          requestID: model.requestID,
          answerRequestID: model.answerRequestID,
          terminalRequestID: model.terminalRequestID,
          onClear: model.clearQuestionAndAnswer,
          onShake: model.handleShake,
          onShakeActivityChanged: model.setShakeFeedbackActive,
          onDragActivityChanged: model.setDragFeedbackActive,
          isPaused: isShowingInfo && infoSheetDetent == .large,
          isShakeEnabled: !isShowingInfo)
          .frame(width: viewportSide, height: viewportSide)
          .id("oracle-ball-viewport")
          .onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .named("oraclePage"))
          } action: { frame in
            ballViewportFrame = frame
          }
          .accessibilityLabel(
            "Oracle answer: \(model.answer.displayText.replacingOccurrences(of: "\n", with: " "))")
          .offset(y: sceneCompositionOffset)

        OracleHeader {
          openSettings()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 10)
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        AskOracleField(
          text: $model.question,
          isFocused: $isQuestionFocused,
          isSubmitting: model.isSubmitting,
          onSubmit: model.submit)
          .onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .named("oraclePage"))
          } action: { frame in
            questionFieldFrame = frame
          }
          .frame(maxWidth: 420)
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 16)
          .padding(.top, 12)
          .padding(.bottom, isKeyboardVisible ? 8 : bottomDescriptionHeight + 12)
          .background {
            LinearGradient(
              colors: [.black.opacity(0.18), .black.opacity(0.78)],
              startPoint: .top,
              endPoint: .bottom)
              .ignoresSafeArea(edges: .bottom)
          }
      }
      .overlay(alignment: .bottom) {
        VStack(spacing: 12) {
          Text(model.statusMessage ?? model.answerStatus)
            .font(.caption.weight(.medium))
            .tracking(0.5)
            .foregroundStyle(.white.opacity(0.34))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(model.statusMessage ?? model.answerStatus)

          Text("AI MAGIC 8-BALL  ·  ASK WITH INTENT")
            .font(.caption2.weight(.medium))
            .tracking(1.4)
            .foregroundStyle(.white.opacity(0.3))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .onGeometryChange(for: CGFloat.self) { geometry in
          geometry.size.height
        } action: { height in
          bottomDescriptionHeight = height
        }
        .background {
          LinearGradient(
            colors: [.black.opacity(0), .black.opacity(0.72)],
            startPoint: .top,
            endPoint: .bottom)
            .ignoresSafeArea(edges: .bottom)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea(.keyboard, edges: .bottom)
      }
      .contentShape(Rectangle())
      .coordinateSpace(name: "oraclePage")
      .simultaneousGesture(
        SpatialTapGesture(coordinateSpace: .named("oraclePage"))
          .onEnded { tap in
            guard isQuestionFocused, !questionFieldFrame.contains(tap.location) else { return }
            isQuestionFocused = false
          })
      .simultaneousGesture(
        DragGesture(minimumDistance: 36, coordinateSpace: .named("oraclePage"))
          .onEnded { gesture in
            let startsInLowerHalf = gesture.startLocation.y >= proxy.size.height / 2
            let isUpwardSwipe = gesture.translation.height <= -56
            let isMostlyVertical = abs(gesture.translation.width) < abs(gesture.translation.height)
            let startsOnFreeArea = !ballViewportFrame.contains(gesture.startLocation)
              && !questionFieldFrame.contains(gesture.startLocation)
            guard startsInLowerHalf, startsOnFreeArea, isUpwardSwipe, isMostlyVertical else { return }
            isQuestionFocused = false
            openSettings()
          })
      .onGeometryChange(for: CGSize.self) { geometry in
        geometry.size
      } action: { size in
        guard initialBallViewportSide == nil else { return }
        initialBallViewportSide = max(
          1, min(size.width - 16, max(180, size.height - 260)))
      }
      .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
        withAnimation(.easeOut(duration: 0.2)) {
          isKeyboardVisible = keyboardReachesBottomEdge(
            notification,
            containerFrame: proxy.frame(in: .global))
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
        withAnimation(.easeOut(duration: 0.2)) {
          isKeyboardVisible = false
        }
      }
    }
    .a11yRoot("oracle")
    .preferredColorScheme(.dark)
    .sheet(isPresented: $isShowingInfo) {
      OracleInfoSheet(
        apiKey: model.configuredAPIKey,
        providerDescription: model.providerDescription,
        historyEntries: model.historyEntries,
        selectedDetent: $infoSheetDetent,
        onSave: model.saveAPIKey,
        onRepeatHistoryEntry: model.repeatQuestion,
        onDeleteHistoryEntry: model.deleteHistoryEntry,
        onClearHistory: model.clearHistory)
        .presentationDetents([.medium, .large], selection: $infoSheetDetent)
        .presentationDragIndicator(.visible)
    }
    .onOpenURL { url in
      guard url.scheme == "oracleball", url.host == "random" else { return }
      model.handleWidgetPrediction()
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { model.refreshHistory() }
    }
  }

  private func openSettings() {
    infoSheetDetent = .medium
    isShowingInfo = true
  }

  private func keyboardReachesBottomEdge(
    _ notification: Notification,
    containerFrame: CGRect
  ) -> Bool {
    guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
    else {
      return false
    }

    let overlapsHorizontally = keyboardFrame.minX < containerFrame.maxX
      && keyboardFrame.maxX > containerFrame.minX
    // SwiftUI may resize the root to end exactly at the keyboard top.
    // Treat that shared edge as an intersection so the field uses keyboard spacing.
    let reachesBottom = keyboardFrame.maxY >= containerFrame.maxY - 1
      && keyboardFrame.minY <= containerFrame.maxY + 1
    return overlapsHorizontally && reachesBottom
  }

}

private struct OracleHeader: View {
  let onInfo: () -> Void
  @ScaledMetric(relativeTo: .body) private var sparkSize: CGFloat = 16
  @ScaledMetric(relativeTo: .body) private var settingsButtonSize: CGFloat = 44

  var body: some View {
    HStack {
      OracleSpark()
        .fill(.white.opacity(0.9))
        .frame(width: sparkSize, height: sparkSize)
        .shadow(color: .oracleLavender.opacity(0.8), radius: 8)
        .accessibilityHidden(true)

      Text("AI MAGIC 8-BALL")
        .font(.caption.weight(.semibold))
        .tracking(1.4)
        .foregroundStyle(.white.opacity(0.66))
        .fixedSize(horizontal: false, vertical: true)

      Spacer()

      Button(action: onInfo) {
        Image(systemName: "info.circle")
          .font(.body.weight(.medium))
          .foregroundStyle(.white.opacity(0.55))
          .frame(width: max(44, settingsButtonSize), height: max(44, settingsButtonSize))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Oracle settings")
      .nestedAccessibilityIdentifier("settings")
    }
    .padding(.horizontal, 16)
    .nestedAccessibilityIdentifier("header")
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
  @State private var isConfirmingHistoryClear = false

  private let savedAPIKey: String
  let providerDescription: String
  let historyEntries: [OracleHistoryEntry]
  @Binding var selectedDetent: PresentationDetent
  let onSave: (String) -> Bool
  let onRepeatHistoryEntry: (String) -> Void
  let onDeleteHistoryEntry: (OracleHistoryEntry.ID) -> Void
  let onClearHistory: () -> Void

  init(
    apiKey: String,
    providerDescription: String,
    historyEntries: [OracleHistoryEntry],
    selectedDetent: Binding<PresentationDetent>,
    onSave: @escaping (String) -> Bool,
    onRepeatHistoryEntry: @escaping (String) -> Void,
    onDeleteHistoryEntry: @escaping (OracleHistoryEntry.ID) -> Void,
    onClearHistory: @escaping () -> Void
  ) {
    _apiKey = State(initialValue: apiKey)
    _isConfigured = State(initialValue: !apiKey.isEmpty)
    savedAPIKey = apiKey
    self.providerDescription = providerDescription
    self.historyEntries = historyEntries
    self._selectedDetent = selectedDetent
    self.onSave = onSave
    self.onRepeatHistoryEntry = onRepeatHistoryEntry
    self.onDeleteHistoryEntry = onDeleteHistoryEntry
    self.onClearHistory = onClearHistory
  }

  var body: some View {
    NavigationStack {
    List {
      Section {
        VStack(alignment: .leading, spacing: selectedDetent == .large ? 16 : 8) {
          HStack {
            Text("Oracle settings")
              .font(.title3.weight(.semibold))
              .nestedAccessibilityIdentifier("title")
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
          .lineLimit(nil)
          .fixedSize(horizontal: false, vertical: true)
          .layoutPriority(1)

          Link(destination: URL(string: "https://typesafe.ai")!) {
            Label("Learn more at TypeSafe.ai", systemImage: "arrow.up.right.square")
              .font(.subheadline.weight(.medium))
          }
          .nestedAccessibilityIdentifier("learn-more")

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
              .nestedAccessibilityIdentifier("api-key")
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
            .nestedAccessibilityIdentifier("clear-key")

            Spacer()

            Button("Save") {
              if onSave(apiKey) {
                isConfigured = true
                dismiss()
              }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSaveAPIKey)
            .nestedAccessibilityIdentifier("save-key")
          }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
        .listRowSeparator(.hidden)
      }
      .textCase(nil)

      if selectedDetent == .large {
        Section {
          historyHeader
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 8))

          if historyEntries.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
              Text("No questions yet")
                .font(.subheadline.weight(.medium))
              Text("Your questions and answers will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
          } else {
            ForEach(historyEntries) { entry in
              NavigationLink {
                OraclePipelineDetailView(entry: entry)
              } label: {
                OracleHistoryRow(entry: entry)
              }
              .tint(.oracleLavender)
              .nestedAccessibilityIdentifier("history.entry.\(entry.id.uuidString)")
              .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
              .listRowSeparator(.visible, edges: .bottom)
              .listRowSeparatorTint(.white.opacity(0.12))
              .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                  dismiss()
                  onRepeatHistoryEntry(entry.question)
                } label: {
                  Label("Repeat", systemImage: "arrow.clockwise")
                }
                .tint(.oracleLavender)
              }
              .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                  onDeleteHistoryEntry(entry.id)
                } label: {
                  Label("Delete", systemImage: "trash")
                }
              }
            }
          }
        }
        .textCase(nil)
      }
    }
    .listStyle(.insetGrouped)
    .listSectionSpacing(.compact)
    .scrollContentBackground(.hidden)
    .background(Color.clear)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if selectedDetent != .large {
        historyHeader
          .padding(.leading, 20)
          .padding(.trailing, 8)
          .padding(.vertical, 8)
          .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
          .padding(.horizontal, 16)
          .padding(.top, 8)
      }
    }
    .confirmationDialog(
      "Delete all question history?",
      isPresented: $isConfirmingHistoryClear,
      titleVisibility: .visible
    ) {
      Button("Delete All", role: .destructive, action: onClearHistory)
      Button("Cancel", role: .cancel) {}
    }
    .toolbar(.hidden, for: .navigationBar)
    }
    .a11yRoot("oracle.settings")
  }

  private var canSaveAPIKey: Bool {
    let candidate = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    return !candidate.isEmpty && candidate != savedAPIKey
  }

  private var historyHeader: some View {
    HStack {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("History")
          .font(.headline)

        if !historyEntries.isEmpty {
          Text("• \(historyEntries.count)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      Button {
        isConfirmingHistoryClear = true
      } label: {
        Image(systemName: "trash")
          .foregroundColor(historyEntries.isEmpty ? Color.secondary : Color.red)
          .frame(width: 40, height: 36)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(historyEntries.isEmpty)
      .accessibilityLabel("Delete all history")
      .nestedAccessibilityIdentifier("delete-all")
    }
    .nestedAccessibilityIdentifier("history")
  }
}

private struct OracleHistoryRow: View {
  let entry: OracleHistoryEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(entry.question.isEmpty ? String(localized: "Random answer") : entry.question)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)

      Text(entry.answer)
        .font(.subheadline)
        .foregroundStyle(Color.oracleLavender)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 8) {
        Text(String(localized: String.LocalizationValue(entry.mode)))
        Text("·")
        Text(String(localized: String.LocalizationValue(entry.source)))
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer(minLength: 4)
        Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
          .lineLimit(1)
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }
}

#Preview {
  OraclePage()
}
