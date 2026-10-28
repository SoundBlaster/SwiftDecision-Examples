import Foundation
import NestedA11yIDs
import OracleHistory
import OraclePresentation
import SwiftUI
import UIKit

/// Pilot composition keeps the scene and composer at stable structural positions.
struct OraclePilotPage: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.scenePhase) private var scenePhase
  let model: OraclePageModel
  @FocusState private var isQuestionFocused: Bool
  @State private var restingHeight: CGFloat = 0
  @State private var isKeyboardVisible = false
  @State private var questionFrame: CGRect = .zero
  @State private var showsInfo = false
  @State private var infoDetent: PresentationDetent = .medium
  @State private var focusAfterSheetDismissal = false
  @State private var selectedHistoryEntry: OracleHistoryEntry?

  var body: some View {
    GeometryReader { geometry in
      let frames = OraclePilotFrames(
        geometry: geometry, restingHeight: restingHeight,
        hasRegularWidth: horizontalSizeClass == .regular,
        usesAccessibilityTextSize: dynamicTypeSize.isAccessibilitySize)
      let headerOnBall = frames.ball.width >= 200 && frames.ball.height >= 80
      let headerHeight: CGFloat = headerOnBall ? 48 : 0
      let side = max(1, min(frames.ball.width - 24, frames.ball.height - headerHeight - 24))
      // Keep RealityView's drawable stable while the fold changes the layout.
      // Resize the rendered scene instead of resizing its underlying viewport.
      let sceneViewportSide: CGFloat = 512
      let sceneScale = side / sceneViewportSide * (frames.plan == .tabletop ? 1.4 : 1)
      let isSideBySide = frames.plan == .expandedPanes || frames.plan == .book
      // In the wide layout, center the sphere in the visible pane. Other
      // arrangements leave extra room for the header above the scene.
      let ballOffset: CGFloat = isSideBySide ? 0 : frames.plan == .tabletop ? -side * 0.06
        : headerHeight / 2 + min(side * 0.06, max(0, frames.ball.height - headerHeight - side) / 2)
      // Leave breathing room below the vertical system status area, but let the
      // composer reclaim that space in a short or keyboard-reduced viewport.
      let needsStatusClearance = OracleStatusAreaClearanceSpec().isSatisfiedBy(.init(
        plan: frames.plan, isKeyboardVisible: isKeyboardVisible))
      let controlsTopInset: CGFloat = needsStatusClearance
        ? min(72, max(0, frames.controls.height - 180)) : 0
      let showsBall = OracleBallVisibilitySpec().isSatisfiedBy(Double(side))
      let showsHistory = OracleInlineHistorySpec().isSatisfiedBy(.init(
        plan: frames.plan, controlsHeight: Double(frames.controls.height),
        isKeyboardVisible: isKeyboardVisible,
        usesAccessibilityTextSize: dynamicTypeSize.isAccessibilitySize))

      ZStack(alignment: .topLeading) {
        OracleCosmicBackground()

        OracleBallViewport(
          answer: model.answer.displayText,
          requestID: model.requestID,
          answerRequestID: model.answerRequestID,
          terminalRequestID: model.terminalRequestID,
          onClear: model.clearQuestionAndAnswer,
          onShake: model.handleShake,
          onShakeActivityChanged: model.setShakeFeedbackActive,
          onDragEnded: model.stopDragFeedback,
          onDragMovement: model.noteDragMovement,
          isPaused: !showsBall || (showsInfo && infoDetent == .large)
            || selectedHistoryEntry != nil,
          isShakeEnabled: !showsInfo && selectedHistoryEntry == nil && showsBall)
          .frame(width: sceneViewportSide, height: sceneViewportSide)
          .scaleEffect(sceneScale)
          .offset(y: ballOffset)
          .frame(width: frames.ball.width, height: frames.ball.height)
          .clipped()
          .contentShape(Rectangle())
          .position(x: frames.ball.midX, y: frames.ball.midY)
          .opacity(showsBall ? 1 : 0)
          .allowsHitTesting(showsBall)
          .accessibilityHidden(!showsBall)
          .nestedAccessibilityIdentifier("ball")

        if headerOnBall {
          OracleHeader {
            isQuestionFocused = false
            infoDetent = .medium
            showsInfo = true
          }
          .frame(width: frames.ball.width, height: headerHeight)
          .position(x: frames.ball.midX, y: frames.ball.minY + headerHeight / 2)
        }

        OraclePilotControls(
          model: model, isQuestionFocused: $isQuestionFocused,
          showsHistory: showsHistory,
          showsHeader: !headerOnBall,
          isExpanded: frames.plan.supportsInlineHistory,
          showsFooter: !frames.plan.supportsInlineHistory && !isKeyboardVisible,
          topInset: controlsTopInset,
          showsTextAnswer: !showsBall,
          onInfo: {
            isQuestionFocused = false
            infoDetent = .medium
            showsInfo = true
          },
          onQuestionFrameChanged: { questionFrame = $0 },
          onHistorySelection: { selectedHistoryEntry = $0 })
          .frame(width: frames.controls.width, height: frames.controls.height)
          .clipped()
          .position(x: frames.controls.midX, y: frames.controls.midY)
      }
      .coordinateSpace(name: "oraclePilot")
      .contentShape(Rectangle())
      .simultaneousGesture(
        SpatialTapGesture(coordinateSpace: .named("oraclePilot"))
          .onEnded { tap in
            if isQuestionFocused && !questionFrame.contains(tap.location) {
              isQuestionFocused = false
            }
          })
      .simultaneousGesture(
        DragGesture(minimumDistance: 36, coordinateSpace: .named("oraclePilot"))
          .onEnded { gesture in
            let startsInLowerHalf = gesture.startLocation.y >= geometry.size.height / 2
            let isUpwardSwipe = gesture.translation.height <= -56
            let isMostlyVertical = abs(gesture.translation.width) < abs(gesture.translation.height)
            let startsOnFreeArea = !frames.ball.contains(gesture.startLocation)
              && !frames.controls.contains(gesture.startLocation)
            guard startsInLowerHalf, startsOnFreeArea, isUpwardSwipe, isMostlyVertical else { return }
            isQuestionFocused = false
            infoDetent = .medium
            showsInfo = true
          })
      .onReceive(NotificationCenter.default.publisher(
        for: UIResponder.keyboardWillChangeFrameNotification)
      ) { notification in
        isKeyboardVisible = keyboardTouchesBottom(
          notification, viewport: geometry.frame(in: .global))
      }
      .onReceive(NotificationCenter.default.publisher(
        for: UIResponder.keyboardWillHideNotification)
      ) { _ in
        isKeyboardVisible = false
      }
    }
    .background {
      // Read inside the keyboard-ignoring region, so typing does not report the
      // reduced viewport as the resting height or collapse ordinary wide panes.
      GeometryReader { restingGeometry in
        Color.clear
          .onChange(of: restingGeometry.size.height, initial: true) { _, height in
            restingHeight = height
          }
      }
      .ignoresSafeArea(.keyboard)
    }
    .a11yRoot("oracle")
    .preferredColorScheme(.dark)
    .task { await model.prepareProvider() }
    .sheet(isPresented: $showsInfo, onDismiss: sheetDismissed) {
      OracleInfoSheet(
        apiKey: model.configuredAPIKey,
        inferenceModel: model,
        historyEntries: model.historyEntries,
        selectedDetent: $infoDetent,
        onSave: model.saveAPIKey,
        onRepeatHistoryEntry: model.repeatQuestion,
        onDeleteHistoryEntry: model.deleteHistoryEntry,
        onClearHistory: model.clearHistory)
        .presentationDetents([.medium, .large], selection: $infoDetent)
        .presentationDragIndicator(.visible)
    }
    .sheet(item: $selectedHistoryEntry, onDismiss: sheetDismissed) { entry in
      NavigationStack {
        OraclePipelineDetailView(entry: entry)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { selectedHistoryEntry = nil }
            }
          }
      }
    }
    .onOpenURL { url in
      guard url.scheme == "oracleball", url.host == "random" else { return }
      model.handleWidgetPrediction()
      let wasShowingHistory = selectedHistoryEntry != nil
      selectedHistoryEntry = nil
      if showsInfo || wasShowingHistory {
        focusAfterSheetDismissal = true
        showsInfo = false
      } else {
        focusQuestion()
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { model.refreshHistory() }
    }
  }

  private func keyboardTouchesBottom(_ notification: Notification, viewport: CGRect) -> Bool {
    guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
    else { return false }
    return frame.minX < viewport.maxX && frame.maxX > viewport.minX
      && frame.maxY >= viewport.maxY - 1 && frame.minY <= viewport.maxY + 1
  }

  private func sheetDismissed() {
    guard focusAfterSheetDismissal else { return }
    focusAfterSheetDismissal = false
    focusQuestion()
  }

  private func focusQuestion() {
    Task { @MainActor in
      await Task.yield()
      isQuestionFocused = true
    }
  }
}

private struct OraclePilotControls: View {
  @Bindable var model: OraclePageModel
  let isQuestionFocused: FocusState<Bool>.Binding
  let showsHistory: Bool
  let showsHeader: Bool
  let isExpanded: Bool
  let showsFooter: Bool
  let topInset: CGFloat
  let showsTextAnswer: Bool
  let onInfo: () -> Void
  let onQuestionFrameChanged: (CGRect) -> Void
  let onHistorySelection: (OracleHistoryEntry) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if showsHeader { OracleHeader(onInfo: onInfo) }

        AskOracleField(
          text: $model.question, isFocused: isQuestionFocused,
          isSubmitting: model.isSubmitting, isPreparingModel: model.isPreparingModel,
          onSubmit: model.submit)
          .frame(maxWidth: 420)
          .frame(maxWidth: .infinity)
          .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named("oraclePilot"))
          } action: { onQuestionFrameChanged($0) }

        if showsTextAnswer && !model.answer.displayText.isEmpty {
          Text(model.answer.displayText.replacingOccurrences(of: "\n", with: " "))
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.oracleLavender)
            .fixedSize(horizontal: false, vertical: true)
        }

        Text(model.statusMessage ?? model.answerStatus)
          .font(.caption.weight(.medium))
          .foregroundStyle(.white.opacity(0.7))
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .center)
          .nestedAccessibilityIdentifier("status")

        if showsFooter {
          Text("AI MAGIC 8-BALL  ·  ASK WITH INTENT")
            .font(.caption2.weight(.medium))
            .tracking(1.4)
            .foregroundStyle(.white.opacity(0.3))
            .frame(maxWidth: .infinity)
        }

        if showsHistory {
          OraclePilotHistory(model: model, onSelection: onHistorySelection)
        }
      }
      .padding(16)
      .padding(.top, topInset)
      .frame(maxWidth: 520)
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
    .background(.black.opacity(isExpanded ? 0.18 : 0), in: RoundedRectangle(cornerRadius: 24))
    .nestedAccessibilityIdentifier("controls")
  }
}

private struct OraclePilotHistory: View {
  let model: OraclePageModel
  let onSelection: (OracleHistoryEntry) -> Void
  @State private var confirmsClear = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("History")
          .font(.headline)
        if !model.historyEntries.isEmpty {
          Text("• \(model.historyEntries.count)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Spacer()
        OracleHistoryExportMenu(entries: model.historyEntries)
          .labelStyle(.iconOnly)
          .frame(width: 44, height: 44)
        Button(role: .destructive) { confirmsClear = true } label: {
          Image(systemName: "trash").frame(width: 44, height: 44)
        }
        .disabled(model.historyEntries.isEmpty)
        .accessibilityLabel("Delete all history")
      }
      if model.historyEntries.isEmpty {
        Text("Your questions and answers will appear here.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .padding(.vertical, 12)
      } else {
        ForEach(model.historyEntries) { entry in
          Divider()
          Button { onSelection(entry) } label: {
            HStack {
              OracleHistoryRow(entry: entry)
              Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
          }
          .buttonStyle(.plain)
          .nestedAccessibilityIdentifier("history.entry.\(entry.id.uuidString)")
          .contextMenu {
            Button("Repeat", systemImage: "arrow.clockwise") {
              model.repeatQuestion(entry.question)
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
              model.deleteHistoryEntry(id: entry.id)
            }
          }
        }
      }
    }
    .padding(.horizontal, 16)
    .background(Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .confirmationDialog("Delete all question history?", isPresented: $confirmsClear,
                        titleVisibility: .visible) {
      Button("Delete All", role: .destructive, action: model.clearHistory)
      Button("Cancel", role: .cancel) {}
    }
  }
}

/// Geometry is owned by the UI; the policy receives only usable region dimensions.
private struct OraclePilotFrames {
  let plan: OracleLayoutPlan
  let ball: CGRect
  let controls: CGRect

  init(
    geometry: GeometryProxy, restingHeight: CGFloat,
    hasRegularWidth: Bool, usesAccessibilityTextSize: Bool
  ) {
    let bounds = CGRect(origin: .zero, size: geometry.size)
    var fold: CGRect?
#if ORACLE_HAS_RESERVED_REGIONS
    if #available(iOS 27.1, *) {
      fold = geometry.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
        .first { $0.isActive && $0.frame.intersects(bounds) }?.frame.intersection(bounds)
      if let value = fold, value.isEmpty { fold = nil }
    }
#endif
    let before: CGRect
    let after: CGRect
    let division: OracleLayoutContext.Division?
    if let fold {
      let vertical = fold.height >= fold.width
      before = CGRect(
        x: 0, y: 0,
        width: vertical ? fold.minX : bounds.width,
        height: vertical ? bounds.height : fold.minY)
      after = CGRect(
        x: vertical ? fold.maxX : 0, y: vertical ? 0 : fold.maxY,
        width: vertical ? max(0, bounds.width - fold.maxX) : bounds.width,
        height: vertical ? bounds.height : max(0, bounds.height - fold.maxY))
      division = .init(
        axis: vertical ? .vertical : .horizontal,
        before: .init(width: before.width, height: before.height),
        after: .init(width: after.width, height: after.height))
    } else {
      before = bounds
      after = bounds
      division = nil
    }
    let context = OracleLayoutContext(
      width: bounds.width, height: bounds.height,
      restingHeight: max(restingHeight, bounds.height),
      hasRegularWidth: hasRegularWidth,
      usesAccessibilityTextSize: usesAccessibilityTextSize, division: division)
    plan = OracleLayoutPolicy().decide(context) ?? .singlePane
    switch plan {
    case .book, .tabletop:
      ball = before.insetBy(dx: 8, dy: 8)
      controls = after.insetBy(dx: 8, dy: 8)
    case .expandedPanes:
      let split = bounds.width * 0.54
      ball = CGRect(x: 0, y: 0, width: split - 12, height: bounds.height)
      controls = CGRect(x: split + 12, y: 8,
        width: max(0, bounds.width - split - 20), height: max(0, bounds.height - 16))
    case .singlePane, .focusedBeforeFold, .focusedAfterFold:
      let region = plan == .focusedBeforeFold ? before
        : plan == .focusedAfterFold ? after : bounds
      let controlHeight = min(region.height, max(150, min(190, region.height * 0.25)))
      let ballHeight = max(0, region.height - controlHeight)
      ball = CGRect(x: region.minX, y: region.minY, width: region.width, height: ballHeight)
      controls = CGRect(x: region.minX + 8, y: region.minY + ballHeight,
        width: max(0, region.width - 16), height: controlHeight)
    }
  }
}
