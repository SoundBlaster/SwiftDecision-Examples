import CityChainGame
import SwiftUI

struct CityChainPage: View {
  let model: CityChainPageModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @Environment(\.scenePhase) private var scenePhase
  @State private var showsNewTripConfirmation = false
  @State private var showsAtlas = false
  @State private var isMapDetailPresented = false
  @State private var showsMapDetailSheet = false
  @State private var showsFullScreenMap = false
  @State private var selectedAtlasCity: USCity?
  @State private var selectedAtlasFact: ScoutFact?
  @State private var atlasFactReactionID: UInt64 = 0
  @Namespace private var atlasMapTransitionNamespace
  @FocusState private var isCityFocused: Bool

  var body: some View {
    let snapshot = model.snapshot
    let suggestions = suggestedCities(for: snapshot)
    NavigationStack {
      GeometryReader { geometry in
        let usesColumns = horizontalSizeClass == .regular
          && verticalSizeClass == .regular
          && geometry.size.width >= 700
          && !dynamicTypeSize.isAccessibilitySize
        let openMapFromScout = {
          if usesColumns { showsFullScreenMap = true }
          else { showsMapDetailSheet = true }
        }

        Group {
          if usesColumns {
            HStack(alignment: .top, spacing: 18) {
              CityAtlasMapView(
                visitedCities: snapshot?.usedCities ?? [],
                presentation: model.scoutPresentation,
                selectedCity: $selectedAtlasCity,
                transitionNamespace: atlasMapTransitionNamespace,
                onOpenMapDetail: openMapDetail,
                onHapticInteraction: model.recordHapticInteraction,
                onTapScout: model.isScoutIdle ? openMapFromScout : nil,
                feedbackMessage: nil,
                feedbackFact: nil,
                feedbackIsFinished: snapshot?.isFinished == true,
                onDismissFeedback: model.dismissTurnFeedback)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .simultaneousGesture(TapGesture().onEnded {
                  if isCityFocused { isCityFocused = false }
                })

              CityChainGamePane(
                model: model, snapshot: snapshot, suggestions: suggestions,
                onTapScout: model.isScoutIdle ? openMapFromScout : nil,
                onShowAtlas: { showsAtlas = true },
                onShowMap: { showsMapDetailSheet = true },
                onRequestNewTrip: { showsNewTripConfirmation = true },
                isCityFocused: $isCityFocused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 18)
          } else {
            CityChainGamePane(
              model: model, snapshot: snapshot, suggestions: suggestions,
              onTapScout: model.isScoutIdle ? openMapFromScout : nil,
              onShowAtlas: { showsAtlas = true },
              onShowMap: { showsMapDetailSheet = true },
              onRequestNewTrip: { showsNewTripConfirmation = true },
              isCityFocused: $isCityFocused)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CityChainBackdrop())
      }
      .navigationDestination(isPresented: $isMapDetailPresented) {
        cityMapDetailDestination
      }
    }
    .sheet(isPresented: $showsAtlas) {
      CityAtlasView(snapshot: model.snapshot, isSubmitting: model.isSubmitting) { city in
        model.recordHapticInteraction(.suggestedCitySelected)
        model.cityInput = city.name
      }
      .toolbar(.visible, for: .navigationBar)
    }
    .sheet(isPresented: $showsMapDetailSheet) {
      cityMapDetail
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    .fullScreenCover(isPresented: $showsFullScreenMap) {
      cityMapDetail
    }
    .onChange(of: snapshot?.usedCities.last, initial: true) { _, latestCity in
      selectedAtlasCity = latestCity
      clearAtlasFact()
    }
    .onChange(of: model.scoutPresentation.reactionID) {
      if model.scoutPresentation.pose == .tryAnother {
        AccessibilityNotification.Announcement(model.statusMessage).post()
      }
    }
#if DEBUG
    .alert(
      "Debug fixture problem",
      isPresented: Binding(
        get: { model.debugFixtureDiagnostic != nil },
        set: { if !$0 { model.dismissDebugFixtureDiagnostic() } }))
    {
      Button("OK", role: .cancel) { model.dismissDebugFixtureDiagnostic() }
    } message: {
      Text(model.debugFixtureDiagnostic ?? "")
    }
#endif
    .confirmationDialog(
      "Start a new road trip?", isPresented: $showsNewTripConfirmation, titleVisibility: .visible
    ) {
      Button("Start new trip") {
        Task { await model.startNewRound() }
      }
      Button("Keep exploring", role: .cancel) {}
    } message: {
      Text("Your current route will be cleared.")
    }
    .task {
      await model.load()
#if DEBUG
      if model.shouldFocusInputAfterLoad {
        try? await Task.sleep(for: .milliseconds(400))
        isCityFocused = true
      }
#endif
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase != .active else { return }
      Task { await model.flushPendingAutosave() }
    }
    .preferredColorScheme(.light)
    .sensoryFeedback(trigger: model.hapticRevision) { _, _ in
      switch model.latestHapticEvent {
      case .scoutThinking:
        .impact(weight: .light, intensity: 0.55)
      case .scoutReplied, .hintUnlocked:
        .success
      case .turnRejected:
        .warning
      case .roundWon:
        .success
      case .newRoundStarted:
        .selection
      case .toolbarButtonPressed, .suggestedCitySelected, .hintRevealed,
           .hintsPopoverDismissed, .mapTapped, .mapCitySelected,
           .scoutQuoteDismissed, .mapClosed:
        .impact(weight: .light, intensity: 0.45)
      case nil:
        nil
      }
    }
  }

  private func suggestedCities(for snapshot: CityGameSnapshot?) -> [USCity] {
    let catalog = USCityCatalog.standard.cities
    guard let snapshot else {
      let starterNames = ["Austin", "Boston", "Chicago"]
      return starterNames.compactMap { name in catalog.first { $0.name == name } }
    }

    let used = Set(snapshot.usedCities.map(\.id))
    guard let requiredLetter = snapshot.requiredStartingLetter else {
      if snapshot.usedCities.isEmpty {
        let starterNames = ["Austin", "Boston", "Chicago"]
        return starterNames.compactMap { name in catalog.first { $0.name == name } }
      }
      return Array(catalog.filter { !used.contains($0.id) }.prefix(4))
    }
    return Array(
      catalog
        .filter { $0.firstLetter == requiredLetter && !used.contains($0.id) }
        .prefix(4))
  }

  private func openMapDetail() {
    if #available(iOS 18.0, *) {
      isMapDetailPresented = true
    } else {
      showsMapDetailSheet = true
    }
  }

  @ViewBuilder
  private var cityMapDetailDestination: some View {
    if #available(iOS 18.0, *) {
      cityMapDetail
        .navigationTransition(
          .zoom(sourceID: CityAtlasMapView.transitionSourceID, in: atlasMapTransitionNamespace))
    } else {
      cityMapDetail
    }
  }

  private var cityMapDetail: some View {
    CityAtlasMapDetailView(
      visitedCities: model.snapshot?.usedCities ?? [],
      presentation: ScoutPresentation(
        pose: selectedAtlasFact == nil ? .welcome : .tryAnother,
        reactionID: atlasFactReactionID),
      selectedCity: $selectedAtlasCity,
      fact: selectedAtlasFact,
      onSelectCity: selectAtlasCity,
      onDismissFact: dismissAtlasFact,
      onDismissMap: { model.recordHapticInteraction(.mapClosed) },
      onHapticInteraction: model.recordHapticInteraction) {
        GameBoardWidget(
          cities: model.snapshot?.usedCities ?? [],
          continuations: model.snapshot?.letterContinuations ?? [],
          latestStopFirst: true,
          isScoutThinking: model.hasCommittedPlayerCityForCurrentTurn
            && model.isScoutThinkingStopVisible
            && model.scoutPresentation.pose == .thinking,
          onSelectCity: selectAtlasCity)
          .accessibilityIdentifier("cityAtlas.map.route")
      }
  }

  private func selectAtlasCity(_ city: USCity) {
    model.recordHapticInteraction(.mapCitySelected)
    selectedAtlasCity = city
    selectedAtlasFact = model.atlasFact(for: city)
    atlasFactReactionID &+= 1
  }

  private func dismissAtlasFact() {
    model.recordHapticInteraction(.scoutQuoteDismissed)
    clearAtlasFact()
  }

  private func clearAtlasFact() {
    selectedAtlasFact = nil
    atlasFactReactionID &+= 1
  }
}

/// Content stays anchored at the top while the scrollable viewport and composer
/// follow the keyboard safe area.
private struct CityChainGamePane: View {
  @Bindable var model: CityChainPageModel
  let snapshot: CityGameSnapshot?
  let suggestions: [USCity]
  let onTapScout: (() -> Void)?
  let onShowAtlas: () -> Void
  let onShowMap: () -> Void
  let onRequestNewTrip: () -> Void
  @State private var showsDecisionTrace = false
  @State private var showsCityHintsPopover = false
  @State private var suppressHintsDismissHaptic = false
  @FocusState.Binding var isCityFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @State private var isCityHintsRevealed = false

  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        ScenicRouteJourneyCard(
          cities: snapshot?.usedCities,
          isWaitingForScout: model.isSubmitting && model.hasCommittedPlayerCityForCurrentTurn)
          .accessibilityIdentifier("cityChain.home.lastLeg")
          .overlay {
            RouteScoutGuide(
              message: scoutMessage,
              fact: model.latestScoutFact,
              presentation: model.scoutPresentation,
              onTapScout: onTapScout,
              canDismiss: model.hasTurnFeedback,
              onDismiss: model.dismissTurnFeedback)
              .accessibilityIdentifier("cityChain.home.routeScout")
          }
        LetterPromptCard(snapshot: snapshot, scoutState: model.scoutState)
          .accessibilityIdentifier("cityChain.home.letterPrompt")
        if showsInlineCityHints && !suggestions.isEmpty {
          InlineCityHints(
            cities: suggestions,
            selectedName: model.cityInput,
            isDisabled: model.isSubmitting,
            isHidden: !isCityHintsRevealed,
            onReveal: {
              model.recordHapticInteraction(.hintRevealed)
              withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                isCityHintsRevealed = true
              }
            },
            onSelect: { selectSuggestedCity($0) })
        }
        if snapshot == nil {
          ProgressView("Getting the atlas ready…")
            .tint(CityChainPalette.blue)
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 10)
      .padding(.bottom, 14)
      .frame(maxWidth: 620)
      .frame(maxWidth: .infinity)
    }
    .scrollIndicators(.hidden)
    .scrollDismissesKeyboard(.never)
    .simultaneousGesture(TapGesture().onEnded {
      if isCityFocused { isCityFocused = false }
    })
    .safeAreaInset(edge: .bottom, spacing: 0) {
      CityChainBottomControls(
        model: model, snapshot: snapshot, isCityFocused: $isCityFocused)
        .accessibilityIdentifier("cityChain.home.composer")
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .toolbar {
      if verticalSizeClass == .compact {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            toolbarActions
          } label: {
            Label("Actions", systemImage: "ellipsis.circle")
          }
          .simultaneousGesture(TapGesture().onEnded {
            model.recordHapticInteraction(.toolbarButtonPressed)
          })
          .popover(isPresented: $showsCityHintsPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            cityHintsPopover
          }
        }
      } else {
        ToolbarItemGroup(placement: .topBarTrailing) {
          toolbarActions
            .labelStyle(.iconOnly)
        }
      }
    }
    .onChange(of: snapshot?.usedCities.count) { _, _ in
      isCityHintsRevealed = snapshot?.usedCities.isEmpty != false
      if showsCityHintsPopover { suppressHintsDismissHaptic = true }
      showsCityHintsPopover = false
    }
    .onChange(of: showsCityHintsPopover) { wasPresented, isPresented in
      model.recordHapticInteraction(
        .hintsPopoverVisibilityChanged(
          wasPresented: wasPresented,
          isPresented: isPresented,
          programmaticDismissal: suppressHintsDismissHaptic))
      suppressHintsDismissHaptic = false
    }
#if DEBUG
    .sheet(isPresented: $showsDecisionTrace) {
      CityChainPipelineDetailView(stages: model.latestTurnPipeline)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
#endif
  }

  private var showsInlineCityHints: Bool {
    snapshot?.usedCities.isEmpty != false
  }

  private var scoutMessage: String? {
    switch model.scoutState {
    case .preparingTurn:
      return String(localized: "Checking your city…")
    case .thinking:
      return String(localized: "One moment, I'm thinking!")
    case .ready, .celebrating, .tryAnother:
      break
    }
    if model.hasTurnFeedback || model.autosaveErrorMessage != nil
      || model.isSubmitting || snapshot?.isFinished == true || showsInlineCityHints
    {
      return model.statusMessage
    } else {
      return nil
    }
  }

  @ViewBuilder
  private var toolbarActions: some View {
    toolbarButton("City atlas", systemImage: "book.closed", hint: "Browse cities", action: onShowAtlas)
    toolbarButton("Pocket Atlas map", systemImage: "map", hint: "Open the route map", action: onShowMap)
    if !showsInlineCityHints && !suggestions.isEmpty {
      cityHintsToolbarButton
    }
    if snapshot?.usedCities.isEmpty == false || snapshot?.isFinished == true {
      toolbarButton("New trip", systemImage: "arrow.counterclockwise", hint: "Start a new trip after confirmation", isDisabled: model.isSubmitting, action: onRequestNewTrip)
    }
#if DEBUG
    if model.isDebugThinkingCapture {
      toolbarButton("Exit capture", systemImage: "xmark", hint: "Leave the paused thinking fixture", action: { Task { await model.exitDebugThinkingCapture() } })
    }
    if !model.latestTurnPipeline.isEmpty {
      toolbarButton("Decision trace", systemImage: "point.3.connected.trianglepath.dotted", hint: "Inspect the latest game decision trace", action: { showsDecisionTrace = true })
    }
#endif
  }

  @ViewBuilder
  private var cityHintsToolbarButton: some View {
    let button = toolbarButton("City hints", systemImage: "lightbulb", hint: "Reveal suggested cities", isDisabled: model.isSubmitting) {
      isCityHintsRevealed = true
      showsCityHintsPopover = true
    }
    if verticalSizeClass == .compact {
      button
    } else {
      button.popover(isPresented: $showsCityHintsPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
        cityHintsPopover
      }
    }
  }

  private var cityHintsPopover: some View {
    CityHintsPopover(
      cities: suggestions, selectedName: model.cityInput, isDisabled: model.isSubmitting,
      isHidden: !isCityHintsRevealed,
      onReveal: {
        model.recordHapticInteraction(.hintRevealed)
        isCityHintsRevealed = true
      },
      onSelect: { selectSuggestedCity($0, dismissingPopover: true) })
    .presentationCompactAdaptation(.popover)
  }

  private func selectSuggestedCity(_ city: USCity, dismissingPopover: Bool = false) {
    model.recordHapticInteraction(.suggestedCitySelected)
    if dismissingPopover {
      suppressHintsDismissHaptic = true
      showsCityHintsPopover = false
    }
    model.cityInput = city.name
  }

  private func toolbarButton(
    _ title: String,
    systemImage: String,
    hint: String,
    isDisabled: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button {
      model.recordHapticInteraction(.toolbarButtonPressed)
      action()
    } label: {
      Label(title, systemImage: systemImage)
    }
    .accessibilityHint(hint)
    .disabled(isDisabled)
  }

  private var latestScoutCity: USCity? {
    guard let cities = snapshot?.usedCities else { return nil }
    return Array(cities.enumerated()).last(where: { !$0.offset.isMultiple(of: 2) })?.element
  }

}

private struct CityChainBottomControls: View {
  @Bindable var model: CityChainPageModel
  let snapshot: CityGameSnapshot?
  @FocusState.Binding var isCityFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 0) {
      if snapshot?.isFinished == true {
        Button {
          Task { await model.startNewRound() }
        } label: {
          Label("Play again", systemImage: "arrow.clockwise")
            .font(.title3.weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(CityChainPalette.blue, in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
      } else {
        SubmitCityForm(
          text: Binding(
            get: { model.cityInput },
            set: { model.cityInput = $0 }),
          isFocused: $isCityFocused,
          isDisabled: model.isSubmitting || snapshot == nil,
          isSubmitting: model.isSubmitting,
          onSubmit: { city in await model.submit(city) })
      }
    }
    .frame(maxWidth: .infinity)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.hasTurnFeedback)
  }
}

/// Fixed space in the main scroll flow; reaction changes never move the next card.
private struct CityScoutSpeechHeader: View {
  let message: String?
  let canDismiss: Bool
  let fact: ScoutFact?
  let presentation: ScoutPresentation
  let onDismiss: () -> Void
  let onTapScout: (() -> Void)?

  var body: some View {
    ScoutSpeechFeedbackView(
      message: message,
      presentation: presentation,
      isCompact: false,
      onDismiss: onDismiss,
      fact: fact,
      companionSize: 176,
      horizontalPadding: 0,
      bubbleAlignment: .top,
      maximumBubbleHeight: 176,
      canDismissMessage: canDismiss,
      onTapScout: onTapScout)
      .frame(height: 200, alignment: .top)
  }
}

/// Preserved city-card variant for future layouts.
private struct CityScoutResponseCard: View {
  let city: USCity?
  let message: String
  let showsMessage: Bool
  let canDismiss: Bool
  let fact: ScoutFact?
  let presentation: ScoutPresentation
  let onDismiss: () -> Void
  let onTapScout: (() -> Void)?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var showsDetails = false

  var body: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 6) {
          Text(city == nil ? "MEET CITY SCOUT" : "SCOUT'S CITY")
            .font(.caption2.weight(.heavy))
            .tracking(0.8)
            .foregroundStyle(CityChainPalette.teal)
          Spacer(minLength: 0)
          if canDismiss {
            Button(action: onDismiss) {
              Image(systemName: "xmark.circle.fill")
                .font(.body)
                .foregroundStyle(CityChainPalette.secondaryInk)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss Scout message")
          }
        }

        if let city {
          Text(city.name)
            .font(.system(.title2, design: .rounded, weight: .bold))
            .foregroundStyle(CityChainPalette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
          if let state = city.state {
            HStack(spacing: 4) {
              Text("\(state.name) · \(state.abbreviation)")
              if city.isStateCapital {
                Label("State capital", systemImage: "star.fill")
                  .labelStyle(.titleAndIcon)
                  .foregroundStyle(CityChainPalette.teal)
              }
            }
            .font(.caption2)
            .foregroundStyle(CityChainPalette.secondaryInk)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
          }
        } else {
          Text("Where to first?")
            .font(.system(.title2, design: .rounded, weight: .bold))
            .foregroundStyle(CityChainPalette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }

        if showsMessage {
          Text(message)
            .font(.caption)
            .foregroundStyle(CityChainPalette.ink)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(message)
            .accessibilityAddTraits(.updatesFrequently)
          Button("Read message details") { showsDetails = true }
            .font(.caption2.weight(.semibold))
            .tint(CityChainPalette.blue)
          if let fact {
            Link(destination: fact.sourceURL) {
              Label("Fact source", systemImage: "arrow.up.right.square")
                .font(.caption2.weight(.semibold))
            }
            .tint(CityChainPalette.teal)
            .accessibilityLabel("Fact source")
            .accessibilityHint("Opens \(fact.sourceTitle)")
          }
        } else if city == nil {
          Text("Take turns with Scout. The last letter points to your next city.")
            .font(.caption)
            .foregroundStyle(CityChainPalette.secondaryInk)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .frame(
        minHeight: dynamicTypeSize.isAccessibilitySize ? 220 : 176,
        maxHeight: dynamicTypeSize.isAccessibilitySize ? 220 : 176,
        alignment: .leading)
      .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 22))
      .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(CityChainPalette.ink.opacity(0.07)))

      Group {
        if let onTapScout {
          Button(action: onTapScout) {
            ScoutView(presentation: presentation, style: .cornerCompanion)
              .frame(width: 144, height: 144)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Open atlas map")
          .accessibilityHint("Shows the map of your road trip")
          .accessibilityIdentifier("cityChain.home.scout")
        } else {
          ScoutView(presentation: presentation, style: .cornerCompanion)
            .frame(width: 144, height: 144)
            .accessibilityIdentifier("cityChain.home.scout")
        }
      }
      .frame(width: 144, height: 144)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .contain)
    .sheet(isPresented: $showsDetails) {
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            Text(message)
              .font(.body)
              .foregroundStyle(CityChainPalette.ink)
              .frame(maxWidth: .infinity, alignment: .leading)
            if let fact {
              Link(destination: fact.sourceURL) {
                Label("Fact source: \(fact.sourceTitle)", systemImage: "arrow.up.right.square")
                  .font(.subheadline.weight(.semibold))
              }
              .tint(CityChainPalette.teal)
            }
          }
          .padding(20)
        }
        .background(CityChainPalette.paper)
        .navigationTitle("Scout's message")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { showsDetails = false }
          }
        }
      }
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
  }
}

private struct InlineCityHints: View {
  let cities: [USCity]
  let selectedName: String
  let isDisabled: Bool
  let isHidden: Bool
  let onReveal: () -> Void
  let onSelect: (USCity) -> Void

  var body: some View {
    ZStack {
      CitySuggestionPicker(cities: cities, selectedName: selectedName, isDisabled: isDisabled, onSelect: onSelect)
        .blur(radius: isHidden ? 7 : 0)
        .allowsHitTesting(!isHidden)
        .accessibilityHidden(isHidden)
      if isHidden {
        Button(action: onReveal) {
          Label("Reveal city hints", systemImage: "eye")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(CityChainPalette.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Reveals suggested cities for this turn")
      }
    }
  }
}

/// Retained static two-stop variant for future layouts.
private struct LastLegCard: View {
  let cities: [USCity]

  var body: some View {
    if cities.count < 2 {
      EmptyRouteCard()
    } else {
      completedRoute
    }
  }

  private var completedRoute: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Your route")
        .font(.system(.headline, design: .rounded, weight: .bold))
        .foregroundStyle(CityChainPalette.ink)

      let endpoints = Array(cities.suffix(2))
      HStack(spacing: 0) {
        Circle()
          .fill(CityChainPalette.blue)
          .frame(width: 14, height: 14)

        ZStack {
          LastLegTrail()
            .stroke(
              CityChainPalette.blue.opacity(0.38),
              style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 7]))
            .frame(height: 22)

          Image(systemName: "car.side.fill")
            .font(.title3)
            .foregroundStyle(CityChainPalette.teal)
            .scaleEffect(x: -1, y: 1)
            .padding(.horizontal, 4)
            .background(.white, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)

        Circle()
          .fill(CityChainPalette.blue)
          .frame(width: 14, height: 14)
      }
      .accessibilityHidden(true)

      HStack(alignment: .top, spacing: 12) {
        LastLegCityLabel(city: endpoints[0], alignment: .leading)
        Spacer(minLength: 8)
        LastLegCityLabel(city: endpoints[1], alignment: .trailing)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Your route from \(endpoints[0].name) to \(endpoints[1].name)")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(.white, in: RoundedRectangle(cornerRadius: 24))
    .overlay {
      RoundedRectangle(cornerRadius: 24)
        .strokeBorder(CityChainPalette.ink.opacity(0.06), lineWidth: 1)
    }
    .shadow(color: CityChainPalette.ink.opacity(0.04), radius: 12, y: 5)
  }
}

private struct LastLegCityLabel: View {
  let city: USCity
  let alignment: HorizontalAlignment

  var body: some View {
    VStack(alignment: alignment, spacing: 3) {
      Text(city.name)
        .font(.system(.subheadline, design: .rounded, weight: .bold))
        .foregroundStyle(CityChainPalette.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Text(city.state.map { "\($0.name) · \($0.abbreviation)" } ?? "United States")
        .font(.caption)
        .foregroundStyle(CityChainPalette.secondaryInk)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
  }
}

private struct LastLegTrail: Shape {
  func path(in rect: CGRect) -> Path {
    Path { path in
      path.move(to: CGPoint(x: rect.minX, y: rect.midY))
      path.addCurve(
        to: CGPoint(x: rect.maxX, y: rect.midY),
        control1: CGPoint(x: rect.width * 0.35, y: rect.minY),
        control2: CGPoint(x: rect.width * 0.65, y: rect.maxY))
    }
  }
}

private struct CityHintsPopover: View {
  let cities: [USCity]
  let selectedName: String
  let isDisabled: Bool
  let isHidden: Bool
  let onReveal: () -> Void
  let onSelect: (USCity) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      CitySuggestionPicker(cities: cities, selectedName: selectedName, isDisabled: isDisabled) {
        onSelect($0)
      }
      .blur(radius: isHidden ? 7 : 0)
      .allowsHitTesting(!isHidden)
      .accessibilityHidden(isHidden)

      if isHidden {
        Button(action: onReveal) {
          Label("Reveal city hints", systemImage: "eye")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(CityChainPalette.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
              RoundedRectangle(cornerRadius: 16)
                .strokeBorder(CityChainPalette.ink.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Reveals suggested cities for this turn")
      }
    }
    .padding(14)
    .frame(width: 330)
    .background(CityChainPalette.paper, in: RoundedRectangle(cornerRadius: 24))
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isHidden)
  }
}

private struct CityChainBackdrop: View {
  var body: some View {
    CityChainPalette.paper
      .overlay(alignment: .top) {
        LinearGradient(
          colors: [CityChainPalette.sky.opacity(0.7), .clear],
          startPoint: .top,
          endPoint: .bottom
        )
        .frame(height: 300)
        .allowsHitTesting(false)
      }
      .ignoresSafeArea(.container)
  }
}

private struct LetterPromptCard: View {
  let snapshot: CityGameSnapshot?
  let scoutState: ScoutState
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .largeTitle) private var letterSize = 56

  var body: some View {
    let isFinished = snapshot?.isFinished == true
    let letter = snapshot?.requiredStartingLetter.map(String.init)
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

    layout {
      VStack(alignment: .leading, spacing: 10) {
        Label(
          isFinished ? "TRIP COMPLETE" : (scoutState.isSubmitting ? "CITY SCOUT'S TURN" : "YOUR TURN"),
          systemImage: isFinished ? "flag.checkered" : "location.fill"
        )
        .font(.caption.weight(.heavy))
        .tracking(1.2)
        .foregroundStyle(CityChainPalette.orange)

        Text(promptTitle)
        .font(.system(.title2, design: .rounded, weight: .bold))
        .fixedSize(horizontal: false, vertical: true)

        if !scoutState.isSubmitting && (isFinished || snapshot?.usedCities.isEmpty != false) {
          Text(
            isFinished
              ? "Every city is a new discovery. Ready for another adventure?"
              : "Take turns with City Scout. The last letter leads to your next city."
          )
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.85))
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      ZStack {
        Text(isFinished ? "★" : (letter ?? "?"))
          .opacity(scoutState.isSubmitting ? 0 : 1)
        if scoutState.isSubmitting {
          ProgressView()
            .controlSize(.large)
            .tint(CityChainPalette.ink)
        }
      }
        .font(.system(size: letterSize, weight: .black, design: .rounded))
        .foregroundStyle(CityChainPalette.ink)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(CityChainPalette.orange, in: RoundedRectangle(cornerRadius: 20))
        .rotationEffect(.degrees(6))
        .shadow(color: .black.opacity(0.12), radius: 0, x: 0, y: 5)
        .accessibilityHidden(true)
    }
    .foregroundStyle(.white)
    .padding(18)
    .background {
      RoundedRectangle(cornerRadius: 28)
        .fill(CityChainPalette.blue.gradient)
    }
    .shadow(color: CityChainPalette.blue.opacity(0.17), radius: 14, y: 8)
    .accessibilityElement(children: .combine)
  }

  private var promptTitle: String {
    if snapshot?.isFinished == true { return String(localized: "You did it!") }
    switch scoutState {
    case .preparingTurn:
      return String(localized: "Checking your city…")
    case .thinking:
      return String(localized: "Scout is thinking…")
    case .ready, .celebrating, .tryAnother:
      if let letter = snapshot?.requiredStartingLetter {
        return String(localized: "Start with \(String(letter))")
      }
      return String(localized: "First stop: anywhere.")
    }
  }
}

private struct CitySuggestionPicker: View {
  let cities: [USCity]
  let selectedName: String
  let isDisabled: Bool
  let onSelect: (USCity) -> Void
  @ScaledMetric(relativeTo: .subheadline) private var cardWidth = 160

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Try one of these")
          .font(.system(.headline, design: .rounded, weight: .bold))
        Spacer()
        Image(systemName: "hand.tap")
          .foregroundStyle(CityChainPalette.secondaryInk)
          .accessibilityHidden(true)
      }
      .foregroundStyle(CityChainPalette.ink)

      ScrollView(.horizontal) {
        HStack(alignment: .top, spacing: 10) {
          ForEach(cities) { city in
            CitySuggestionCard(city: city, isSelected: selectedName == city.name) {
              onSelect(city)
            }
            .frame(width: cardWidth)
            .disabled(isDisabled)
          }
        }
        .padding(2)
      }
      .scrollIndicators(.hidden)
    }
  }
}

private struct CitySuggestionCard: View {
  let city: USCity
  let isSelected: Bool
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Image(systemName: city.isStateCapital ? "star.fill" : "mappin.circle.fill")
            .foregroundStyle(city.isStateCapital ? CityChainPalette.teal : CityChainPalette.blue)
          Spacer()
          Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
            .foregroundStyle(CityChainPalette.blue)
        }
        .font(.subheadline)
        Text(city.name)
          .font(.system(.headline, design: .rounded, weight: .bold))
          .foregroundStyle(CityChainPalette.ink)
        Text(city.state.map { "\($0.name) · \($0.abbreviation)" } ?? "United States")
          .font(.caption)
          .foregroundStyle(CityChainPalette.secondaryInk)
        Text(city.isStateCapital ? "State capital" : "Explore this city")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(CityChainPalette.teal)
      }
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(14)
      .background(
        isSelected ? CityChainPalette.sky : .white, in: RoundedRectangle(cornerRadius: 18)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 18)
          .strokeBorder(
            isSelected ? CityChainPalette.blue : CityChainPalette.ink.opacity(0.08),
            lineWidth: isSelected ? 2 : 1)
      }
      .contentShape(RoundedRectangle(cornerRadius: 18))
    }
    .buttonStyle(.plain)
    .accessibilityHint("Copies this city into the city name field")
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}

#if DEBUG
private struct CityChainPipelineDetailView: View {
  let stages: [CityGamePipelineStage]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        if stages.isEmpty {
          ContentUnavailableView("No decision trace", systemImage: "point.3.connected.trianglepath.dotted")
        }

        ForEach(stages) { stage in
          Section(stage.title) {
            if let summary = stage.summary {
              Label(summary, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ForEach(stage.details) { detail in
              LabeledContent(detail.label, value: detail.value)
                .font(.caption)
            }

            ForEach(stage.events) { event in
              eventRow(event, in: stage.events)
            }
          }
        }
      }
      .listStyle(.insetGrouped)
      .navigationTitle("Decision pipeline")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private func eventRow(_ event: CityGameTraceEvent, in events: [CityGameTraceEvent]) -> some View {
    let isDecision = event.kind == .decision
    var metadata = [isDecision ? "Decision" : "Rule check"]
    if let outcome = event.outcome { metadata.append(outcome) }
    if let duration = event.durationNanoseconds { metadata.append(format(duration)) }
    if let elapsed = event.elapsedNanoseconds { metadata.append("at +\(format(elapsed))") }

    return HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol(for: event))
        .foregroundStyle(tint(for: event))
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 3) {
        Text(event.name)
          .font(.subheadline)
          .fixedSize(horizontal: false, vertical: true)
        Text(metadata.joined(separator: " · "))
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
        if let detail = event.detail, !detail.isEmpty {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.leading, CGFloat(depth(of: event, in: events)) * 14)
    .accessibilityElement(children: .combine)
  }

  private func depth(of event: CityGameTraceEvent, in events: [CityGameTraceEvent]) -> Int {
    let parents = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0.parentID) })
    var depth = 0
    var parent = event.parentID
    var visited: Set<String> = []
    while let id = parent, visited.insert(id).inserted {
      depth += 1
      parent = parents[id] ?? nil
    }
    return depth
  }

  private func symbol(for event: CityGameTraceEvent) -> String {
    guard event.kind == .specification else { return "arrow.triangle.branch" }
    return switch event.outcome {
    case "Satisfied", "Selected": "checkmark.circle.fill"
    case "Not satisfied", "No match": "xmark.circle"
    case "Failed": "exclamationmark.circle.fill"
    default: "circle"
    }
  }

  private func tint(for event: CityGameTraceEvent) -> Color {
    guard event.kind == .specification else { return CityChainPalette.blue }
    return switch event.outcome {
    case "Satisfied", "Selected": CityChainPalette.teal
    case "Not satisfied", "No match", "Failed": Color.orange
    default: Color.secondary
    }
  }

  private func format(_ nanoseconds: UInt64) -> String {
    if nanoseconds < 1_000_000 {
      return String(format: "%.1f µs", Double(nanoseconds) / 1_000)
    }
    return String(format: "%.2f ms", Double(nanoseconds) / 1_000_000)
  }
}
#endif

#Preview("First stop") {
  CityChainPage(model: CityChainPageModel.preview())
}

#Preview("Larger text") {
  CityChainPage(model: CityChainPageModel.preview())
    .environment(\.dynamicTypeSize, .accessibility1)
}

@available(iOS 18.0, *)
private struct StartedTripPreviewModifier: PreviewModifier {
  typealias Context = CityChainPageModel

  static func makeSharedContext() async throws -> CityChainPageModel {
    let model = CityChainPageModel.preview()
    await model.load()
    _ = await model.submit("Austin")
    return model
  }

  func body(content: Content, context: CityChainPageModel) -> some View {
    CityChainPage(model: context)
  }
}

@available(iOS 18.0, *)
#Preview("Pocket Atlas — started trip", traits: .modifier(StartedTripPreviewModifier())) {
  EmptyView()
}

@available(iOS 18.0, *)
private struct ThinkingTripPreviewModifier: PreviewModifier {
  typealias Context = CityChainPageModel

  static func makeSharedContext() async throws -> CityChainPageModel {
    let fixture = CityGameFixture(
      route: [.init(role: .player, city: "Austin")], phase: .thinking)
    let model = CityChainPageModel.preview(fixture: fixture)
    await model.load()
    return model
  }

  func body(content: Content, context: CityChainPageModel) -> some View {
    CityChainPage(model: context)
  }
}

@available(iOS 18.0, *)
#Preview("Scout is thinking", traits: .modifier(ThinkingTripPreviewModifier())) {
  EmptyView()
}

#Preview("Route placeholders", traits: .sizeThatFitsLayout) {
  VStack(spacing: 24) {
    EmptyRouteCard()
      .frame(width: 350)
    EmptyRouteCard()
      .frame(width: 660)
  }
  .padding(24)
  .background(CityChainPalette.paper)
}

#Preview("Narrow route placeholder", traits: .sizeThatFitsLayout) {
  EmptyRouteCard()
    .frame(width: 260)
    .padding(24)
    .background(CityChainPalette.paper)
}
