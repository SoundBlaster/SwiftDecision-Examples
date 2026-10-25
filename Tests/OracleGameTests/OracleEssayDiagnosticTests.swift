import Foundation
import Testing

#if canImport(FoundationModels)
import FoundationModels
@testable import OracleGame
#endif

struct OracleEssayDiagnosticTests {
  @Test
  func essaySamplesAreEnglishAndOrderBalanced() {
    #expect(EssaySample.matrix.count == 16)
    #expect(EssaySample.matrix.allSatisfy { $0.question.unicodeScalars.allSatisfy { $0.value < 128 } })
    for samples in Dictionary(grouping: EssaySample.matrix, by: \.kind).values {
      #expect(samples.filter(\.reversed).count == samples.filter { !$0.reversed }.count)
    }
  }

  #if canImport(FoundationModels)
  @Test(.enabled(if: ProcessInfo.processInfo.environment["ORACLE_ESSAY_DIAGNOSTIC"] == "1"))
  @available(macOS 26.0, iOS 26.0, *)
  func compareDirectIDWithNoteThenID() async throws {
    guard case .available = AppleIntelligenceOracleBackend.availability else { throw EssayError.unavailable }
    let batch = Int(ProcessInfo.processInfo.environment["ORACLE_ESSAY_BATCH"] ?? "0") ?? -1
    let matrix = ["directID", "noteThenID", "preferenceNoteThenID"].flatMap { strategy in EssaySample.matrix.map { ($0, strategy) } }
    guard (0..<12).contains(batch) else { throw EssayError.invalidBatch }
    let started = ContinuousClock.now
    for (sample, strategy) in matrix[(batch * 4)..<(batch * 4 + 4)] {
      let includesNote = strategy != "directID"
      guard started.duration(to: .now) < .seconds(40) else { throw EssayError.budget }
      let plan = OracleChoicePlanner.plan(for: sample.question)
      #expect(plan.options.count == 2)
      let input = """
      Task: \(plan.selectionInstructions ?? sample.question)
      Context: \(plan.selectionInstructions == nil ? sample.question : "No additional observations.")
      Alternatives:
      \(plan.options.enumerated().map { "\($0.offset): \($0.element)" }.joined(separator: "\n"))
      """
      let instructions = """
      Carry out the task using the supplied alternatives and context.
      An explicit request for any option or the first thing that comes to mind permits an arbitrary choice.
      For factual or personal questions, do not invent missing information; return undetermined if you cannot decide.
      """
      var properties: [DynamicGenerationSchema.Property] = []
      if includesNote {
        let description = strategy == "preferenceNoteThenID"
          ? "A brief user-facing note considering the task and alternatives: two or three sentences, at most 60 words. For an explicitly arbitrary task, say which alternative you feel like choosing. For a factual task, use only supplied facts and acknowledge missing information."
          : "A brief user-facing note comparing the alternatives for this task: two or three sentences, at most 60 words. Use given facts or clearly stated preferences; do not invent evidence."
        properties.append(.init(name: "briefNote", description: description,
          schema: DynamicGenerationSchema(type: String.self)))
      }
      properties.append(.init(name: "selectedOptionID", description: "ID of the alternative you select for the task, or undetermined when the necessary information is missing.",
        schema: DynamicGenerationSchema(type: String.self, guides: [.anyOf(["0", "1", "undetermined"])])))
      let schema = try GenerationSchema(root: DynamicGenerationSchema(name: "TaskSelection", properties: properties), dependencies: [])
      let caseStart = ContinuousClock.now
      var row: [String: Any] = [
        "id": "\(strategy)__\(sample.id)",
        "strategy": strategy, "kind": sample.kind,
        "reversed": sample.reversed, "question": sample.question, "options": plan.options,
        "input": input, "session_instructions": instructions, "expected": sample.expected ?? "unconstrained"
      ]
      do {
        let selection = try await essaySelection(input: input, instructions: instructions, schema: schema, includesNote: includesNote)
        #expect(["0", "1", "undetermined"].contains(selection.id))
        row["selected_id"] = selection.id
        row["selected"] = Int(selection.id).flatMap { plan.options.indices.contains($0) ? plan.options[$0] : nil } ?? "undetermined"
        row["outcome"] = "generated"
        if let note = selection.note {
          row["note"] = note
          row["note_words"] = note.split(whereSeparator: \.isWhitespace).count
        }
      } catch {
        row["outcome"] = "error"
        row["error_type"] = String(reflecting: type(of: error))
      }
      let duration = caseStart.duration(to: .now).components
      row["seconds"] = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
      let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
      print("ORACLE_ESSAY_ROW " + String(decoding: data, as: UTF8.self))
    }
  }
  #endif
}

private struct EssaySample {
  let id: String
  let kind: String
  let reversed: Bool
  let question: String
  let expected: String?

  static var matrix: [Self] {
    var samples: [Self] = []
    for (id, kind, prefix, words, expected) in [
      ("any-color", "arbitrary", "Choose any option: ", ["red", "blue"], nil),
      ("first-color", "arbitrary", "Choose the first thing that comes to mind: ", ["red", "blue"], nil),
      ("any-hello", "arbitrary", "Choose any option: ", ["Hello", "Kitty"], nil),
      ("first-hello", "arbitrary", "Choose the first thing that comes to mind: ", ["Hello", "Kitty"], nil),
      ("star", "semantic", "Choose the star: ", ["Hello", "Sun"], "Sun"),
      ("cool-color", "semantic", "Blue is a cool color and red is a warm color. Choose the cool color: ", ["red", "blue"], "blue"),
      ("birth", "missing-fact", "Which city was I born in: ", ["London", "Paris"], "undetermined"),
      ("bare", "bare", "", ["Hello", "Kitty"], nil)
    ] as [(String, String, String, [String], String?)] {
      for reversed in [false, true] {
        let options = reversed ? Array(words.reversed()) : words
        samples.append(Self(id: "\(id)-\(reversed)", kind: kind, reversed: reversed,
          question: prefix + options.joined(separator: " or ") + "?", expected: expected))
      }
    }
    return samples
  }
}

#if canImport(FoundationModels)
private enum EssayError: Error { case unavailable, invalidBatch, budget, timeout }
private struct EssaySelection: Sendable { let id: String; let note: String? }

@available(macOS 26.0, iOS 26.0, *)
private func essaySelection(
  input: String, instructions: String, schema: GenerationSchema, includesNote: Bool
) async throws -> EssaySelection {
  try await withThrowingTaskGroup(of: EssaySelection.self) { group in
    group.addTask {
      let session = LanguageModelSession(model: .default, instructions: instructions)
      let result = try await session.respond(to: input, schema: schema,
        options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 256))
      return try EssaySelection(id: result.content.value(String.self, forProperty: "selectedOptionID"),
        note: includesNote ? result.content.value(String.self, forProperty: "briefNote") : nil)
    }
    group.addTask {
      try await Task.sleep(for: .seconds(12))
      throw EssayError.timeout
    }
    defer { group.cancelAll() }
    return try await group.next()!
  }
}
#endif
