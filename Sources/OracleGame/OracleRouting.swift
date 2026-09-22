import Foundation

struct OracleChoicePlan: Sendable, Hashable {
  let options: [String]
}

struct OracleRoutingContext: Sendable {
  let mode: OracleMode
  let choicePlan: OracleChoicePlan
  let asksForProbability: Bool
}

enum OracleChoicePlanner {
  private static let separators = [
    " versus ", " vs. ", " vs ", " or ", " and ",
    " или ", " и ",
  ]
  private static let choiceCues = [
    "which ",
    "choose ",
    "pick ",
    "between ",
    "versus ",
    " vs ",
    "alternative",
    "options",
    "should i ",
    "should we ",
    "какой ",
    "выбери ",
    "выбрать ",
    "между ",
    "вариант",
  ]

  static func plan(for question: String) -> OracleChoicePlan {
    let normalized = normalize(question)
    let matchingText = normalized.lowercased()
    let hasChoiceCue = choiceCues.contains(where: matchingText.contains)
    let hasAlternativeSeparator = separators.contains {
      matchingText.range(of: $0) != nil
    }
    guard !normalized.isEmpty, hasChoiceCue || hasAlternativeSeparator
    else {
      return OracleChoicePlan(options: [])
    }

    var body = normalized
    if let colon = body.lastIndex(of: ":") {
      body = String(body[body.index(after: colon)...])
    } else if matchingText.hasPrefix("which "), let comma = body.firstIndex(of: ",") {
      body = String(body[body.index(after: comma)...])
    }
    body = removeLeadingPhrases(from: body)

    let candidates = normalizeInterrogativeCandidates(
      splitCandidates(body),
      body: body)
      .map(cleanCandidate)
      .filter { !$0.isEmpty }
    var unique: [String] = []
    for candidate in candidates where !unique.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
      unique.append(candidate)
    }
    guard (2 ... 5).contains(unique.count) else {
      return OracleChoicePlan(options: [])
    }
    return OracleChoicePlan(options: unique)
  }

  static func asksForProbability(_ question: String) -> Bool {
    let normalized = normalize(question)
    let cues = [
      "how likely",
      "probability",
      "probable",
      "chance",
      "percentage",
      "percent",
      "confidence",
      "odds",
      "on a scale",
    ]
    return cues.contains(where: normalized.lowercased().contains)
  }

  private static func normalize(_ question: String) -> String {
    question
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
  }

  private static func removeLeadingPhrases(from value: String) -> String {
    var result = value
    let phrases = [
      "what should i choose ",
      "what should we choose ",
      "which one should i choose ",
      "which one should we choose ",
      "should i choose ",
      "should we choose ",
      "should i ",
      "should we ",
      "choose ",
      "pick ",
      "что мне выбрать ",
      "что нам выбрать ",
      "что выбрать ",
      "какой вариант выбрать ",
      "выбери ",
      "выбрать ",
    ]
    var didRemove = true
    while didRemove {
      didRemove = false
      let matchingResult = result.lowercased()
      for phrase in phrases where matchingResult.hasPrefix(phrase) {
        result.removeFirst(phrase.count)
        didRemove = true
        break
      }
    }
    return result
  }

  private static func splitCandidates(_ body: String) -> [String] {
    if body.contains(",") {
      return body
        .split(separator: ",")
        .flatMap { part in
          let value = String(part)
          for separator in [" or ", " and ", " или ", " и "] {
            if value.range(of: separator, options: .caseInsensitive) != nil {
              return splitCaseInsensitive(value, separator: separator)
            }
          }
          return [value]
        }
    }
    if (body.lowercased().hasPrefix("between ") && body.range(of: " and ", options: .caseInsensitive) != nil)
      || (body.lowercased().hasPrefix("между ") && body.range(of: " и ", options: .caseInsensitive) != nil)
    {
      if body.lowercased().hasPrefix("между ") {
        return splitCaseInsensitive(String(body.dropFirst("между ".count)), separator: " и ")
      }
      return splitCaseInsensitive(String(body.dropFirst("between ".count)), separator: " and ")
    }
    for separator in separators where separator != " and " {
      if body.range(of: separator, options: .caseInsensitive) != nil {
        return splitCaseInsensitive(body, separator: separator)
      }
    }
    return []
  }

  private static func normalizeInterrogativeCandidates(
    _ candidates: [String],
    body: String
  ) -> [String] {
    guard candidates.count >= 2 else { return candidates }
    let normalized = body.lowercased()
    let interrogativePrefixes = [
      "who ", "what ", "which ", "where ", "when ",
      "кто ", "что ", "какой ", "какая ", "где ", "когда ",
    ]
    guard interrogativePrefixes.contains(where: normalized.hasPrefix) else {
      return candidates
    }

    var result = candidates
    let first = candidates[0].trimmingCharacters(in: .whitespacesAndNewlines)
    let words = first.split(separator: " ")
    guard words.count > 1, let last = words.last else { return candidates }
    result[0] = String(last)
    return result
  }

  private static func splitCaseInsensitive(_ value: String, separator: String) -> [String] {
    var remaining = value
    var parts: [String] = []
    while let range = remaining.range(of: separator, options: .caseInsensitive) {
      parts.append(String(remaining[..<range.lowerBound]))
      remaining = String(remaining[range.upperBound...])
    }
    parts.append(remaining)
    return parts
  }

  private static func cleanCandidate(_ value: String) -> String {
    value
      .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
  }
}
