import CityChainGame
import SwiftUI

struct CityChainPage: View {
  let model: CityChainPageModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showsNewTripConfirmation = false

  var body: some View {
    let snapshot = model.snapshot
    let suggestions = suggestedCities(for: snapshot)

    NavigationStack {
      ZStack {
        CityChainBackdrop()

        ScrollView {
          VStack(spacing: 22) {
            CityTripHeader()
            LetterPromptCard(snapshot: snapshot, isSubmitting: model.isSubmitting)

            if !suggestions.isEmpty && snapshot?.isFinished != true {
              CitySuggestionPicker(
                cities: suggestions, selectedName: model.cityInput, isDisabled: model.isSubmitting
              ) { city in
                model.cityInput = city.name
              }
            }

            if let snapshot {
              if model.hasTurnFeedback {
                RoundStatusCard(
                  message: model.isSubmitting ? "Looking for our next stop…" : model.statusMessage,
                  isFinished: snapshot.isFinished)
              }
              GameBoardWidget(cities: snapshot.usedCities)
            } else {
              ProgressView("Getting the atlas ready…")
                .tint(CityChainPalette.blue)
                .frame(maxWidth: .infinity, minHeight: 180)
            }
          }
          .padding(.horizontal, 20)
          .padding(.top, 18)
          .padding(.bottom, 18)
          .frame(maxWidth: 560)
          .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        CityChainBottomControls(model: model, snapshot: snapshot)
      }
      .navigationTitle("City Chain")
      .toolbarTitleDisplayMode(.inline)
      .toolbar {
        if snapshot?.usedCities.isEmpty == false || snapshot?.isFinished == true {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              showsNewTripConfirmation = true
            } label: {
              Label("New trip", systemImage: "arrow.counterclockwise")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
            }
            .disabled(model.isSubmitting)
          }
        }
      }
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
      .animation(
        reduceMotion ? nil : .smooth(duration: 0.25), value: snapshot?.requiredStartingLetter
      )
      .task { await model.load() }
    }
    .preferredColorScheme(.light)
  }

  private func suggestedCities(for snapshot: CityGameSnapshot?) -> [USCity] {
    let catalog = USCityCatalog.standard.cities
    guard let snapshot, let requiredLetter = snapshot.requiredStartingLetter else {
      let starterNames = ["Austin", "Boston", "Chicago"]
      return starterNames.compactMap { name in catalog.first { $0.name == name } }
    }

    let used = Set(snapshot.usedCities.map(\.id))
    return Array(
      catalog
        .filter { $0.firstLetter == requiredLetter && !used.contains($0.id) }
        .prefix(4))
  }
}

private struct CityChainBottomControls: View {
  @Bindable var model: CityChainPageModel
  let snapshot: CityGameSnapshot?

  var body: some View {
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
      .frame(maxWidth: 560)
      .frame(maxWidth: .infinity)
      .background(.regularMaterial)
    } else {
      SubmitCityForm(
        text: Binding(
          get: { model.cityInput },
          set: { model.cityInput = $0 }),
        isDisabled: model.isSubmitting || snapshot == nil,
        isSubmitting: model.isSubmitting,
        onSubmit: { city in await model.submit(city) })
    }
  }
}

private struct CityChainBackdrop: View {
  var body: some View {
    CityChainPalette.paper
      .ignoresSafeArea()
      .overlay(alignment: .top) {
        LinearGradient(
          colors: [CityChainPalette.sky.opacity(0.7), .clear],
          startPoint: .top,
          endPoint: .bottom
        )
        .frame(height: 300)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
      }
  }
}

private struct CityTripHeader: View {
  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      Image(systemName: "map.fill")
        .font(.system(.title, design: .rounded, weight: .semibold))
        .foregroundStyle(CityChainPalette.blue)
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .rotationEffect(.degrees(-7))
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text("A little American adventure")
          .font(.caption.weight(.semibold))
          .foregroundStyle(CityChainPalette.blue)
        Text("Let's go places.")
          .font(.system(.largeTitle, design: .rounded, weight: .heavy))
          .foregroundStyle(CityChainPalette.ink)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
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

        Text(
          isFinished
            ? "Every city is a new discovery. Ready for another adventure?"
            : "Take turns with City Scout. The last letter leads to your next city."
        )
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.85))
        .fixedSize(horizontal: false, vertical: true)
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

private struct RoundStatusCard: View {
  let message: String
  let isFinished: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: isFinished ? "trophy.fill" : "binoculars.fill")
        .font(.title3)
        .foregroundStyle(CityChainPalette.teal)
        .padding(10)
        .background(CityChainPalette.mint, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 5) {
        Text(isFinished ? "What a trip!" : "City Scout")
          .font(.system(.subheadline, design: .rounded, weight: .bold))
        Text(message)
          .font(.callout)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.updatesFrequently)
      }
      .foregroundStyle(CityChainPalette.ink)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .modifier(CityChainCard())
  }
}

#Preview("First stop") {
  CityChainPage(model: AppDependencies().makePageModel())
}

#Preview("Larger text") {
  CityChainPage(model: AppDependencies().makePageModel())
    .environment(\.dynamicTypeSize, .accessibility1)
}
