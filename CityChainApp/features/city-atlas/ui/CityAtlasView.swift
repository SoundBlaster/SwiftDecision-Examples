import CityChainGame
import SwiftUI

/// A searchable companion to the game's curated catalog, available throughout a round.
struct CityAtlasView: View {
  let snapshot: CityGameSnapshot?
  let isSubmitting: Bool
  let onSelect: (USCity) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var searchText = ""

  private let cities = USCityCatalog.standard.cities.sorted { $0.name < $1.name }

  var body: some View {
    let usedIDs = Set(snapshot?.usedCities.map(\.id) ?? [])
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let matches = cities.filter { city in
      query.isEmpty || city.name.range(
        of: query, options: [.anchored, .caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US")) != nil
    }
    let ready = matches.filter { isReady($0, usedIDs: usedIDs) }
    let others = matches.filter { !isReady($0, usedIDs: usedIDs) }

    NavigationStack {
      List {
        Section {
          Label("Every explorer can use an atlas!", systemImage: "book.closed.fill")
            .font(.headline)
            .foregroundStyle(CityChainPalette.teal)
          Text(instructions)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        if !ready.isEmpty {
          Section("Ready for this turn") {
            ForEach(ready) { city in
              Button {
                onSelect(city)
                dismiss()
              } label: {
                CityAtlasRow(city: city, note: nil, canSelect: true)
              }
              .buttonStyle(.plain)
              .accessibilityHint("Copies this city into the city name field. You can send it when ready.")
            }
          }
        }

        if !others.isEmpty {
          Section("Explore the atlas") {
            ForEach(others) { city in
              CityAtlasRow(
                city: city,
                note: note(for: city, usedIDs: usedIDs),
                canSelect: false)
            }
          }
        }

        if matches.isEmpty {
          ContentUnavailableView.search(text: searchText)
        }
      }
      .listStyle(.insetGrouped)
      .searchable(text: $searchText, prompt: "City starts with…")
      .navigationTitle("City atlas")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .tint(CityChainPalette.blue)
  }

  private var instructions: String {
    if snapshot?.isFinished == true {
      return "Our trip is complete. Keep exploring, or start a new trip to pick another city."
    }
    if isSubmitting || snapshot == nil {
      return "Browse while Scout gets ready. You can pick a city when it's your turn."
    }
    let explanation = snapshot?.letterContinuations.last?.explanation.map { $0 + " " } ?? ""
    if let letter = snapshot?.requiredStartingLetter {
      return explanation + "Find a new city starting with \(letter). Tap a ready city to copy its name, then send it when you're ready."
    }
    if snapshot?.usedCities.isEmpty == false {
      return explanation + "Choose any new city. Tap its name to copy it, then send it when ready."
    }
    return "Pick any city for your first stop. Tap its name to copy it, then send it when you're ready."
  }

  private func isReady(_ city: USCity, usedIDs: Set<String>) -> Bool {
    guard let snapshot, !snapshot.isFinished, !isSubmitting,
      !usedIDs.contains(city.id) else { return false }
    return snapshot.requiredStartingLetter.map { city.firstLetter == $0 } ?? true
  }

  private func note(for city: USCity, usedIDs: Set<String>) -> String? {
    if usedIDs.contains(city.id) { return "Already visited" }
    guard snapshot?.isFinished == false,
      let required = snapshot?.requiredStartingLetter,
      city.firstLetter != required else { return nil }
    return "Starts with \(city.firstLetter.map(String.init) ?? "") · This turn needs \(required)"
  }
}

private struct CityAtlasRow: View {
  let city: USCity
  let note: String?
  let canSelect: Bool

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 5) {
        Text(city.name)
          .font(.system(.headline, design: .rounded))
          .foregroundStyle(CityChainPalette.ink)
        Text(city.state.map { "\($0.name) · \($0.abbreviation)" } ?? "United States")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        if city.isStateCapital {
          Label("State capital", systemImage: "star.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(CityChainPalette.teal)
        }
        if let note {
          Text(note)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)

      if canSelect {
        Image(systemName: "plus.circle.fill")
          .font(.title2)
          .foregroundStyle(CityChainPalette.blue)
          .accessibilityHidden(true)
      }
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

#Preview("City atlas") {
  CityAtlasView(snapshot: nil, isSubmitting: false, onSelect: { _ in })
}
