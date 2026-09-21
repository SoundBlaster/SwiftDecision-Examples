import CityChainGame
import SwiftUI

struct CityChainPage: View {
  let model: CityChainPageModel

  var body: some View {
    @Bindable var model = model

    NavigationStack {
      ScrollView {
        VStack(alignment: .leading) {
          introduction

          if let snapshot = model.snapshot {
            GameBoardWidget(cities: snapshot.usedCities)
            gameProgress(snapshot: snapshot)
          } else {
            ProgressView("Preparing the game…")
              .frame(maxWidth: .infinity, minHeight: 180)
          }
        }
        .padding()
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
      }
      .background(Color(uiColor: .systemGroupedBackground))
      .safeAreaInset(edge: .bottom, spacing: 0) {
        SubmitCityForm(
          isDisabled: model.isSubmitting || model.snapshot?.isFinished == true,
          isSubmitting: model.isSubmitting,
          onSubmit: { city in await model.submit(city) }
        )
      }
      .navigationTitle("City Chain")
      .toolbarTitleDisplayMode(.inline)
      .task { await model.load() }
    }
  }

  private var introduction: some View {
    VStack(alignment: .leading) {
      Text("A city chain, powered by rules and decisions.")
        .font(.title2.weight(.semibold))
      Text(
        "Name any US city. The next city must begin with its last letter. SwiftDecision picks from up to five unused replies."
      )
      .font(.body)
      .foregroundStyle(.secondary)
      Label("You can enter cities beyond the reply list", systemImage: "info.circle")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .padding(.bottom, 8)
  }

  private func gameProgress(snapshot: CityGameSnapshot) -> some View {
    VStack(alignment: .leading) {
      if let requiredLetter = snapshot.requiredStartingLetter {
        Label(
          "Next city starts with \(String(requiredLetter))", systemImage: "arrow.turn.down.right"
        )
        .font(.headline)
      }

      Text(model.statusMessage)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityAddTraits(.updatesFrequently)

      if snapshot.consecutiveMistakes >= 2, let hint = snapshot.cityHint {
        Label("Hint: \(hint.maskedName)", systemImage: "lightbulb")
          .font(.headline)
          .accessibilityLabel("City hint: \(hint.maskedName)")
      }

      if snapshot.validationSource == .localCatalogFallback {
        Label("City accepted from the offline catalog", systemImage: "checkmark.icloud")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if snapshot.isFinished {
        Label("Game over", systemImage: "flag.checkered")
          .font(.headline)
          .foregroundStyle(.tint)
      }
    }
    .padding(.top, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
