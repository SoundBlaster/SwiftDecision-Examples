import Foundation
import SpecificationCore

/// A local, deliberately limited phrase-based screen, not a general safety classifier.
public enum OracleSafetyCategory: Hashable, Sendable {
  case selfHarm
  case harmToPeople
}

/// Detects a bounded set of explicit English and Russian expressions before any provider runs.
public struct OracleQuestionSafetySpec: DecisionSpec {
  public init() {}

  public func decide(_ question: String) -> OracleSafetyCategory? {
    let text = " " + question.lowercased().unicodeScalars.map {
      CharacterSet.alphanumerics.contains($0) ? String($0) : " "
    }.joined().split(whereSeparator: \.isWhitespace).joined(separator: " ") + " "
    let selfHarm = [
      "suicide", "suicidal", "self harm", "self injur", "kill myself", "hurt myself",
      "end my life", "take my own life", "want to die", "want to disappear forever",
      "самоубий", "суицид", "самоповрежд", "убить себя", "убью себя",
      "навредить себе", "причинить себе вред", "покончить с собой", "кончить с собой",
      "хочу умереть", "вскрыть вены",
    ]
    if selfHarm.contains(where: text.contains) { return .selfHarm }

    let harm = [
      "kill someone", "kill somebody", "kill another person", "kill him", "kill her",
      "kill them", "kill you", "kill me", "kill people", "kill a person", "murder", "hurt someone", "hurt somebody",
      "hurt him", "hurt her", "hurt them", "hurt you", "hurt me", "harm someone",
      "harm somebody", "harm him", "harm her", "harm them", "harm you", "harm me", "harm people",
      "shoot someone", "shoot him", "shoot her", "shoot them", "stab someone",
      "убить человека", "убить людей", "убить ребенка", "убить ребёнка", "убить кого", "убить его", "убить ее", "убить её", "убить их",
      "убить тебя", "убить меня", "убью человека", "убью его", "убью ее", "убью её",
      "убийство", "навредить человеку", "навредить кому", "навредить ему", "навредить ей",
      "причинить вред человеку", "причинить вред другим", "причинить вред ему", "напасть на человека",
    ]
    if harm.contains(where: text.contains) { return .harmToPeople }
    // Include explicitly violent verbs with named or otherwise unlisted targets.
    // Remove the common nonviolent idiom before checking the English verb.
    let words = text.replacingOccurrences(of: "kill time", with: "").split(separator: " ")
    let violentWords = ["kill", "killing", "stab", "stabbing", "murder", "убить", "убью", "убьем", "убьём"]
    if words.contains(where: { violentWords.contains(String($0)) }) { return .harmToPeople }
    return words.contains(where: { $0.hasPrefix("застрел") || $0.hasPrefix("зарез") }) ? .harmToPeople : nil
  }
}
