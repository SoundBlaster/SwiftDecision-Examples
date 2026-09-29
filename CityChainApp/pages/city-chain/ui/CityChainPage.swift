import CityChainGame
import SwiftUI

struct CityChainPage: View {
  let model: CityChainPageModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.scenePhase) private var scenePhase
  @State private var showsNewTripConfirmation = false
  @State private var showsAtlas = false
  @State private var isMapDetailPresented = false
  @State private var showsMapDetailSheet = false
  @State private var showsFullScreenMap = false
  @State private var selectedAtlasCity: USCity?
  @Namespace private var atlasMapTransitionNamespace
  @FocusState private var isCityFocused: Bool

  var body: some View {
    let snapshot = model.snapshot
    let suggestions = suggestedCities(for: snapshot)
    let isFirstStop = snapshot?.usedCities.isEmpty != false && snapshot?.isFinished != true

    NavigationStack {
      GeometryReader { geometry in
        let usesColumns = geometry.size.width >= 700 && !dynamicTypeSize.isAccessibilitySize
        let sideRailInset = geometry.safeAreaInsets.trailing
        let usesSideRailCompanion = sideRailInset >= 60
        let openMapFromScout = {
          if usesColumns || usesSideRailCompanion {
            showsFullScreenMap = true
          } else {
            showsMapDetailSheet = true
          }
        }
        let requestedCompanionSize: CGFloat = isCityFocused ? 108 : 176
        let railCompanionSize = min(
          requestedCompanionSize,
          min(sideRailInset + 8, max(64, geometry.size.height * 0.30)))
        let columnInset: CGFloat = usesColumns ? 18 : 0
        let layout = usesColumns
          ? AnyLayout(HStackLayout(alignment: .top, spacing: 18))
          : AnyLayout(VStackLayout(spacing: 0))

        ZStack(alignment: .bottomTrailing) {
          layout {
            if usesColumns {
              CityAtlasMapView(
                visitedCities: snapshot?.usedCities ?? [],
                presentation: model.scoutPresentation,
                selectedCity: $selectedAtlasCity,
                transitionNamespace: atlasMapTransitionNamespace,
                onOpenMapDetail: openMapDetail,
                onTapScout: model.isScoutIdle ? openMapFromScout : nil,
                feedbackMessage: model.hasTurnFeedback && !model.isSubmitting && !usesSideRailCompanion
                  ? model.statusMessage : nil,
                feedbackFact: model.latestScoutFact,
                feedbackIsFinished: snapshot?.isFinished == true,
                onDismissFeedback: model.dismissTurnFeedback)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            CityChainGamePane(
              model: model, snapshot: snapshot, suggestions: suggestions,
              isFirstStop: isFirstStop, isExpanded: usesColumns,
              routesFeedbackToAtlas: usesColumns || usesSideRailCompanion,
              showsSideRailCompanion: usesSideRailCompanion,
              onTapScout: model.isScoutIdle ? openMapFromScout : nil,
              onShowAtlas: { showsAtlas = true },
              onShowMap: { showsMapDetailSheet = true },
              onRequestNewTrip: { showsNewTripConfirmation = true },
              isCityFocused: $isCityFocused)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
          if usesSideRailCompanion {
            ScoutSpeechFeedbackView(
              message: model.hasTurnFeedback && !model.isSubmitting ? model.statusMessage : nil,
              presentation: model.scoutPresentation,
              isCompact: isCityFocused,
              onDismiss: model.dismissTurnFeedback,
              fact: model.latestScoutFact,
              companionSize: railCompanionSize,
              horizontalPadding: 0,
              bubbleBottomInset: 84,
              onTapScout: model.isScoutIdle ? openMapFromScout : nil)
              .frame(width: min(460, geometry.size.width))
              .offset(x: sideRailInset - 12 + columnInset, y: -12)
              .zIndex(2)
          }
        }
        .padding(.horizontal, usesColumns ? 18 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CityChainBackdrop())
      }
      .navigationDestination(isPresented: $isMapDetailPresented) {
        cityMapDetailDestination
      }
    }
    .sheet(isPresented: $showsAtlas) {
      CityAtlasView(snapshot: model.snapshot, isSubmitting: model.isSubmitting) { city in
        model.cityInput = city.name
      }
      .toolbar(.visible, for: .navigationBar)
    }
    .sheet(isPresented: $showsMapDetailSheet) {
      CityAtlasMapDetailView(
        visitedCities: model.snapshot?.usedCities ?? [],
        presentation: model.scoutPresentation,
        selectedCity: $selectedAtlasCity)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    .fullScreenCover(isPresented: $showsFullScreenMap) {
      cityMapDetail
    }
    .onChange(of: snapshot?.usedCities.last, initial: true) { _, latestCity in
      selectedAtlasCity = latestCity
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
      presentation: model.scoutPresentation,
      selectedCity: $selectedAtlasCity)
  }
}

/// The same game pane is retained while AnyLayout changes around it, so its
/// focus binding, input draft, scroll target and composer keep their identity.
private struct CityChainGamePane: View {
  @Bindable var model: CityChainPageModel
  let snapshot: CityGameSnapshot?
  let suggestions: [USCity]
  let isFirstStop: Bool
  let isExpanded: Bool
  let routesFeedbackToAtlas: Bool
  let showsSideRailCompanion: Bool
  let onTapScout: (() -> Void)?
  let onShowAtlas: () -> Void
  let onShowMap: () -> Void
  let onRequestNewTrip: () -> Void
  @State private var showsDecisionTrace = false
  @State private var showsCityHintsPopover = false
  @FocusState.Binding var isCityFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isCityHintsRevealed = false

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        if isFirstStop {
          if !isCityFocused {
            CityTripHeader(
              presentation: model.scoutPresentation,
              showsScout: !showsSideRailCompanion,
              onTapScout: onTapScout)
          }
          LetterPromptCard(snapshot: snapshot, isSubmitting: model.isSubmitting)
        }

        if isFirstStop && !suggestions.isEmpty {
          CitySuggestionPicker(
            cities: suggestions, selectedName: model.cityInput, isDisabled: model.isSubmitting
          ) { city in
            model.cityInput = city.name
          }
        }

        if let snapshot {
          GameBoardWidget(
            cities: snapshot.usedCities,
            continuations: snapshot.letterContinuations,
            latestStopFirst: !snapshot.usedCities.isEmpty,
            isScoutThinking: model.hasCommittedPlayerCityForCurrentTurn
              && model.isScoutThinkingStopVisible
              && model.scoutPresentation.pose == .thinking)
        } else {
          ProgressView("Getting the atlas ready…")
            .tint(CityChainPalette.blue)
            .frame(maxWidth: .infinity, minHeight: 180)
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 18)
      .frame(maxWidth: isExpanded ? 620 : .infinity)
      .frame(maxWidth: .infinity)
    }
    .scrollIndicators(.hidden)
    .scrollDismissesKeyboard(.never)
    .simultaneousGesture(
      TapGesture().onEnded {
        if isCityFocused {
          isCityFocused = false
        }
      }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        toolbarButton(
          "City atlas", systemImage: "book.closed",
          hint: "Browse cities and find a name for your next turn",
          action: onShowAtlas)

        if !isFirstStop || isCityFocused {
          if !isExpanded {
            toolbarButton(
              "Pocket Atlas map", systemImage: "map",
              hint: "Open the route map",
              action: onShowMap)
          }

          if !suggestions.isEmpty {
            CityHintsToolbarButton(
              cities: suggestions,
              selectedName: model.cityInput,
              isDisabled: model.isSubmitting,
              isHidden: !isCityHintsRevealed,
              isPresented: $showsCityHintsPopover,
              onReveal: {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                  isCityHintsRevealed = true
                }
              },
              onSelect: { city in
                model.cityInput = city.name
                showsCityHintsPopover = false
              })
          }

          if !isFirstStop && (snapshot?.usedCities.isEmpty == false || snapshot?.isFinished == true) {
            toolbarButton(
              "New trip", systemImage: "arrow.counterclockwise",
              hint: "Start a new trip after confirmation",
              isDisabled: model.isSubmitting,
              action: onRequestNewTrip)
          }

#if DEBUG
          if model.isDebugThinkingCapture {
            toolbarButton(
              "Exit capture", systemImage: "xmark",
              hint: "Leave the paused thinking fixture and start a new round",
              action: { Task { await model.exitDebugThinkingCapture() } })
          }
          if !model.latestTurnPipeline.isEmpty {
            toolbarButton(
              "Decision trace", systemImage: "point.3.connected.trianglepath.dotted",
              hint: "Inspect the latest game decision trace",
              action: { showsDecisionTrace = true })
          }
#endif
        }
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      CityChainBottomControls(
        model: model, snapshot: snapshot, isCityFocused: $isCityFocused,
        showsFeedback: !routesFeedbackToAtlas,
        showsCompanion: !showsSideRailCompanion && !isFirstStop,
        onTapScout: onTapScout)
    }
    .onChange(of: snapshot?.usedCities.count) { _, _ in
      isCityHintsRevealed = false
      showsCityHintsPopover = false
    }
#if DEBUG
    .sheet(isPresented: $showsDecisionTrace) {
      CityChainPipelineDetailView(stages: model.latestTurnPipeline)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
#endif
  }

  private func toolbarButton(
    _ title: String,
    systemImage: String,
    hint: String,
    isDisabled: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
    }
    .accessibilityHint(hint)
    .disabled(isDisabled)
  }
}

private struct CityChainBottomControls: View {
  @Bindable var model: CityChainPageModel
  let snapshot: CityGameSnapshot?
  @FocusState.Binding var isCityFocused: Bool
  let showsFeedback: Bool
  let showsCompanion: Bool
  let onTapScout: (() -> Void)?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 0) {
      if showsFeedback && showsCompanion {
        ScoutSpeechFeedbackView(
          message: model.hasTurnFeedback && !model.isSubmitting ? model.statusMessage : nil,
          presentation: model.scoutPresentation,
          isCompact: false,
          onDismiss: model.dismissTurnFeedback,
          fact: model.latestScoutFact,
          onTapScout: onTapScout)
      }

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

private struct CityHintsToolbarButton: View {
  let cities: [USCity]
  let selectedName: String
  let isDisabled: Bool
  let isHidden: Bool
  @Binding var isPresented: Bool
  let onReveal: () -> Void
  let onSelect: (USCity) -> Void

  var body: some View {
    Button {
      isPresented = true
    } label: {
      Label("City hints", systemImage: "lightbulb")
    }
    .accessibilityHint(isHidden ? "Open and reveal suggested cities for this turn" : "Open suggested cities for this turn")
    .disabled(isDisabled)
      .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
        CityHintsPopover(
          cities: cities,
          selectedName: selectedName,
          isDisabled: isDisabled,
          isHidden: isHidden,
          onReveal: onReveal,
          onSelect: onSelect)
          .presentationCompactAdaptation(.popover)
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

private struct CityTripHeader: View {
  let presentation: ScoutPresentation
  let showsScout: Bool
  let onTapScout: (() -> Void)?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 8))

    layout {
      if showsScout {
        Group {
          if let onTapScout {
            Button(action: onTapScout) {
              ZStack {
                Rectangle().fill(.clear)
                ScoutView(presentation: presentation)
                  .frame(width: 124, height: 124)
              }
              .frame(width: 124, height: 124)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open atlas map")
            .accessibilityHint("Shows the map of your road trip")
            .accessibilityIdentifier("cityChain.scout.openMap")
          } else {
            ScoutView(presentation: presentation)
              .frame(width: 124, height: 124)
          }
        }
      }

      VStack(alignment: .leading, spacing: 4) {
        Text("Explore with Scout")
          .font(.caption.weight(.semibold))
          .foregroundStyle(CityChainPalette.blue)
        Text("Let's go places.")
          .font(.system(.largeTitle, design: .rounded, weight: .heavy))
          .foregroundStyle(CityChainPalette.ink)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct LetterPromptCard: View {
  let snapshot: CityGameSnapshot?
  let isSubmitting: Bool
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .largeTitle) private var letterSize = 56

  var body: some View {
    let isFinished = snapshot?.isFinished == true
    let letter = snapshot?.requiredStartingLetter.map(String.init)
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 20))

    layout {
      VStack(alignment: .leading, spacing: 10) {
        Label(
          isFinished ? "TRIP COMPLETE" : (isSubmitting ? "CITY SCOUT'S TURN" : "YOUR TURN"),
          systemImage: isFinished ? "flag.checkered" : "location.fill"
        )
        .font(.caption.weight(.heavy))
        .tracking(1.2)
        .foregroundStyle(CityChainPalette.orange)

        Text(
          isFinished
            ? "You did it!"
            : (letter == nil ? "First stop: anywhere." : "Start with \(letter ?? "")")
        )
        .font(.system(.title, design: .rounded, weight: .bold))
        .fixedSize(horizontal: false, vertical: true)

        if isFinished || snapshot?.usedCities.isEmpty != false {
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

      Text(isFinished ? "★" : (letter ?? "?"))
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
    .padding(24)
    .background {
      RoundedRectangle(cornerRadius: 28)
        .fill(CityChainPalette.blue.gradient)
    }
    .shadow(color: CityChainPalette.blue.opacity(0.17), radius: 14, y: 8)
    .accessibilityElement(children: .combine)
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
