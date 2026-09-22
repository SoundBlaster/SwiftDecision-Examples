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
  private static let separators = [" versus ", " vs. ", " vs ", " or "]
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
  ]

  static func plan(for question: String) -> OracleChoicePlan {
    let normalized = normalize(question)
    guard !normalized.isEmpty,
          choiceCues.contains(where: normalized.contains)
    else {
      return OracleChoicePlan(options: [])
    }

    var body = normalized
    if let colon = body.lastIndex(of: ":") {
      body = String(body[body.index(after: colon)...])
    } else if body.hasPrefix("which "), let comma = body.firstIndex(of: ",") {
      body = String(body[body.index(after: comma)...])
    }
    body = removeLeadingPhrases(from: body)

    let candidates = splitCandidates(body)
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
    return cues.contains(where: normalized.contains)
  }

  private static func normalize(_ question: String) -> String {
    question
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .lowercased()
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
      "choose between ",
      "pick between ",
      "between ",
      "should i ",
      "should we ",
      "choose ",
      "pick ",
    ]
    var didRemove = true
    while didRemove {
      didRemove = false
      for phrase in phrases where result.hasPrefix(phrase) {
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
          if value.contains(" or ") { return value.components(separatedBy: " or ") }
          if value.contains(" and ") { return value.components(separatedBy: " and ") }
          return [value]
        }
    }
    for separator in separators {
      if body.contains(separator) {
        return body.components(separatedBy: separator)
      }
    }
    if body.hasPrefix("between "), body.contains(" and ") {
      return String(body.dropFirst("between ".count)).components(separatedBy: " and ")
    }
    return []
  }

  private static func cleanCandidate(_ value: String) -> String {
    value
      .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
  }
}
