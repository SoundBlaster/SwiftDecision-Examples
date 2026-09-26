import CityChainGame
import SwiftUI

struct CityChainPage: View {
  let model: CityChainPageModel

  var body: some View {
    @Bindable var model = model
    let snapshot = model.snapshot
    let suggestions = suggestedCities(for: snapshot)

    NavigationStack {
      ZStack {
        CityChainBackdrop()

        ScrollView {
          VStack(spacing: 20) {
            CityTripHeader()
            LetterPromptCard(snapshot: snapshot)

            if !suggestions.isEmpty && snapshot?.isFinished != true {
              CitySuggestionPicker(cities: suggestions) { city in
                model.cityInput = city.name
              }
            }

            if let snapshot {
              RoundStatusCard(
                message: model.statusMessage,
                isFinished: snapshot.isFinished)
              GameBoardWidget(cities: snapshot.usedCities)
            } else {
              ProgressView("Getting the atlas ready…")
                .tint(CityChainPalette.blue)
                .frame(maxWidth: .infinity, minHeight: 180)
            }
          }
          .padding(.horizontal, 18)
          .padding(.top, 12)
          .padding(.bottom, 18)
          .frame(maxWidth: 560)
          .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        bottomControls(model: model, snapshot: snapshot)
      }
      .navigationTitle("City Chain")
      .toolbarTitleDisplayMode(.inline)
      .toolbar {
        if snapshot?.usedCities.isEmpty == false || snapshot?.isFinished == true {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              Task { await model.startNewRound() }
            } label: {
              Label("New trip", systemImage: "arrow.counterclockwise")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
            }
            .disabled(model.isSubmitting)
          }
        }
      }
      .task { await model.load() }
    }
    .preferredColorScheme(.light)
  }

  @ViewBuilder
  private func bottomControls(
    model: CityChainPageModel,
    snapshot: CityGameSnapshot?
  ) -> some View {
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

private struct CityChainBackdrop: View {
  var body: some View {
    LinearGradient(
      colors: [CityChainPalette.sky, CityChainPalette.paper, CityChainPalette.mint],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
    .ignoresSafeArea()
    .overlay(alignment: .topTrailing) {
      Image(systemName: "sparkles")
        .font(.system(size: 140, weight: .light))
        .foregroundStyle(.white.opacity(0.42))
        .rotationEffect(.degrees(12))
        .offset(x: 38, y: 28)
        .accessibilityHidden(true)
    }
  }
}

private struct CityTripHeader: View {
  var body: some View {
    VStack(spacing: 10) {
      ZStack {
        Circle()
          .fill(.white.opacity(0.88))
          .frame(width: 68, height: 68)
          .shadow(color: CityChainPalette.blue.opacity(0.14), radius: 16, y: 7)
        Image(systemName: "map.fill")
          .font(.system(size: 30, weight: .semibold))
          .foregroundStyle(CityChainPalette.blue)
      }
      .accessibilityHidden(true)

      Text("Let's explore the U.S.A.!")
        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
        .multilineTextAlignment(.center)
        .foregroundStyle(CityChainPalette.ink)

      Text("Take turns naming cities. Each new city starts where the last one ends.")
        .font(.body)
        .multilineTextAlignment(.center)
        .foregroundStyle(CityChainPalette.ink.opacity(0.72))
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .padding(.bottom, 2)
  }
}

private struct LetterPromptCard: View {
  let snapshot: CityGameSnapshot?

  var body: some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text(snapshot?.requiredStartingLetter == nil ? "Your first stop" : "Your next city")
          .font(.headline.weight(.bold))
          .foregroundStyle(CityChainPalette.ink)
        Text(
          snapshot?.requiredStartingLetter == nil
            ? "Pick a city from the atlas to get started."
            : "Find a city that starts with this letter!"
        )
        .font(.callout)
        .foregroundStyle(CityChainPalette.ink.opacity(0.7))
        .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 8)

      Text(snapshot?.requiredStartingLetter.map { String($0) } ?? "?")
        .font(.system(.largeTitle, design: .rounded, weight: .black))
        .foregroundStyle(.white)
        .frame(width: 76, height: 76)
        .background(CityChainPalette.orange, in: Circle())
        .accessibilityLabel(
          snapshot?.requiredStartingLetter.map { "Start with \($0)" } ?? "Choose any starting letter")
        .contentTransition(.numericText())
    }
    .padding(18)
    .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .shadow(color: CityChainPalette.ink.opacity(0.08), radius: 18, y: 8)
  }
}

private struct CitySuggestionPicker: View {
  let cities: [USCity]
  let onSelect: (USCity) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Need an idea? Pick a city")
        .font(.subheadline.weight(.bold))
        .foregroundStyle(CityChainPalette.ink)

      ScrollView(.horizontal) {
        HStack(spacing: 10) {
          ForEach(cities) { city in
            Button {
              onSelect(city)
            } label: {
              HStack(spacing: 7) {
                Image(systemName: city.isStateCapital ? "star.fill" : "mappin.and.ellipse")
                  .font(.caption.weight(.bold))
                  .foregroundStyle(city.isStateCapital ? CityChainPalette.orange : CityChainPalette.blue)
                Text(city.name)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(CityChainPalette.ink)
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 11)
              .background(.white.opacity(0.92), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
              city.isStateCapital
                ? "\(city.name), state capital of \(city.stateName ?? "")"
                : city.name)
            .frame(minHeight: 44)
          }
        }
      }
      .scrollIndicators(.hidden)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct RoundStatusCard: View {
  let message: String
  let isFinished: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: isFinished ? "trophy.fill" : "bubble.left.and.bubble.right.fill")
        .foregroundStyle(isFinished ? CityChainPalette.orange : CityChainPalette.blue)
        .accessibilityHidden(true)
      Text(message)
        .font(.callout.weight(.medium))
        .foregroundStyle(CityChainPalette.ink)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.updatesFrequently)
      Spacer(minLength: 0)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}
