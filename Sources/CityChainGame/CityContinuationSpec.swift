import Foundation
import SpecificationCore

/// Strict chaining remains available to existing engine clients.
public enum CityContinuationPolicy: Sendable {
  case lastLetter
  case previousAvailableLetter
}

/// Records which letters were exhausted at this point in the trip.
public struct CityLetterContinuation: Sendable, Equatable {
  public let sourceCity: USCity
  public let startingLetter: Character?
  public let skippedLetters: [Character]
}

struct CityContinuationContext {
  let city: USCity
  let catalog: [USCity]
  let usedCityIDs: Set<String>
}

/// Chooses the rightmost letter with unused catalog cities. If every letter is
/// exhausted, nil startingLetter means a free choice, not a lost round.
struct CityContinuationSpec: DecisionSpec {
  let policy: CityContinuationPolicy

  func decide(_ context: CityContinuationContext) -> CityLetterContinuation? {
    let letters = context.city.continuationLetters
    guard let last = letters.first else { return nil }
    switch policy {
    case .lastLetter:
      return CityLetterContinuation(sourceCity: context.city, startingLetter: last, skippedLetters: [])
    case .previousAvailableLetter:
      let unused = UnusedCitySpec(usedIDs: context.usedCityIDs)
      let available = Set(context.catalog.filter { unused.isSatisfiedBy($0) }.compactMap(\.firstLetter))
      let canContinue = AvailableInitialSpec(available: available)
      var skipped: [Character] = []
      for letter in letters {
        if canContinue.isSatisfiedBy(letter) {
          return CityLetterContinuation(
            sourceCity: context.city, startingLetter: letter, skippedLetters: skipped)
        }
        if !skipped.contains(letter) { skipped.append(letter) }
      }
      return CityLetterContinuation(sourceCity: context.city, startingLetter: nil, skippedLetters: skipped)
    }
  }
}

private struct UnusedCitySpec: Specification {
  let usedIDs: Set<String>
  func isSatisfiedBy(_ city: USCity) -> Bool { !usedIDs.contains(city.id) }
}

private struct AvailableInitialSpec: Specification {
  let available: Set<Character>
  func isSatisfiedBy(_ letter: Character) -> Bool { available.contains(letter) }
}
