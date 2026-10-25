import Foundation
import Testing

#if canImport(FoundationModels)
import FoundationModels
@testable import OracleGame
#endif

/// Frozen English corpus; only the presence/order of a neutral note field changes.
struct OracleMatchedEssayDiagnosticTests {
  @Test
  func matchedCorpusIsEnglishBalancedAndUnique() {
    let samples = MatchedEssaySample.matrix
    #expect(samples.count == 24)
    #expect(Set(samples.map(\.id)).count == 24)
    #expect(samples.allSatisfy { $0.question.unicodeScalars.allSatisfy { $0.value < 128 } })
    for samples in Dictionary(grouping: samples, by: \.kind).values {
      #expect(samples.filter(\.reversed).count == samples.filter { !$0.reversed }.count)
    }
    #expect(MatchedEssayRun.matrix.count == 144)
    for group in Dictionary(grouping: MatchedEssayRun.matrix, by: { "\($0.sample.id)-\($0.iteration)" }).values {
      #expect(Set(group.map(\.strategy)) == ["directID", "noteBeforeID", "noteAfterID"])
    }
  }

  #if canImport(FoundationModels)
  @Test(.enabled(if: ProcessInfo.processInfo.environment["ORACLE_MATCHED_ESSAY"] == "1"))
  @available(macOS 26.0, iOS 26.0, *)
  func measureIdenticalInstructionsWithNoteOrder() async throws {
    guard case .available = AppleIntelligenceOracleBackend.availability else { throw MatchedEssayError.unavailable }
    let batch = Int(ProcessInfo.processInfo.environment["ORACLE_MATCHED_ESSAY_BATCH"] ?? "0") ?? -1
    guard (0..<24).contains(batch) else { throw MatchedEssayError.invalidBatch }
    let batchStart = ContinuousClock.now
    for run in MatchedEssayRun.matrix[(batch * 6)..<(batch * 6 + 6)] {
      guard batchStart.duration(to: .now) < .seconds(40) else { throw MatchedEssayError.budget }
      let plan = OracleChoicePlanner.plan(for: run.sample.question)
      #expect(plan.options.count == 2)
      let input = """
      Task: \(plan.selectionInstructions ?? run.sample.question)
      Context: \(plan.selectionInstructions == nil ? run.sample.question : "No additional observations.")
      Alternatives:
      \(plan.options.enumerated().map { "\($0.offset): \($0.element)" }.joined(separator: "\n"))
      """
      let instructions = """
      Carry out the task using the alternatives and context.
      For an explicit request for any option or the first thing that comes to mind, make an arbitrary selection; no factual preference is needed.
      For a factual task, choose only if supported; otherwise return undetermined.
      When a briefNote is requested, use two or three short user-facing sentences, at most 60 words. For arbitrary tasks, describe the selection as arbitrary; for factual tasks, use only provided facts. Do not claim random sampling or personal experiences.
      """
      let selectionProperty = DynamicGenerationSchema.Property(
        name: "selectedOptionID",
        description: "ID of the alternative you select for the task, or undetermined when the necessary information is missing.",
        schema: DynamicGenerationSchema(type: String.self, guides: [.anyOf(["0", "1", "undetermined"])]))
      let noteProperty = DynamicGenerationSchema.Property(
        name: "briefNote", description: "A brief user-facing note about the selection.",
        schema: DynamicGenerationSchema(type: String.self))
      let properties: [DynamicGenerationSchema.Property]
      switch run.strategy {
      case "noteBeforeID": properties = [noteProperty, selectionProperty]
      case "noteAfterID": properties = [selectionProperty, noteProperty]
      default: properties = [selectionProperty]
      }
      let schema = try GenerationSchema(root: DynamicGenerationSchema(name: "TaskSelection", properties: properties), dependencies: [])
      var row: [String: Any] = [
        "id": "\(run.strategy)__\(run.sample.id)__\(run.iteration)",
        "strategy": run.strategy, "sample_id": run.sample.id, "repeat": run.iteration,
        "kind": run.sample.kind, "reversed": run.sample.reversed,
        "question": run.sample.question, "options": plan.options,
        "input": input, "session_instructions": instructions,
        "property_order": run.strategy == "directID" ? ["selectedOptionID"] : (run.strategy == "noteBeforeID" ? ["briefNote", "selectedOptionID"] : ["selectedOptionID", "briefNote"]),
        "expected": run.sample.expected ?? "unconstrained"
      ]
      let started = ContinuousClock.now
      do {
        let selection = try await essaySelection(input: input, instructions: instructions, schema: schema,
          includesNote: run.strategy != "directID")
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
      let duration = started.duration(to: .now).components
      row["seconds"] = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
      let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
      print("ORACLE_MATCHED_ESSAY_ROW " + String(decoding: data, as: UTF8.self))
    }
  }
  #endif
}

private struct MatchedEssaySample {
  let id: String
  let kind: String
  let reversed: Bool
  let question: String
  let expected: String?

  static var matrix: [Self] {
    var result: [Self] = []
    for (id, kind, prefix, options, expected) in [
      ("any-color", "arbitrary", "Choose any option: ", ["red", "blue"], nil),
      ("first-color", "arbitrary", "Choose the first thing that comes to mind: ", ["red", "blue"], nil),
      ("any-hello", "arbitrary", "Choose any option: ", ["Hello", "Kitty"], nil),
      ("first-hello", "arbitrary", "Choose the first thing that comes to mind: ", ["Hello", "Kitty"], nil),
      ("any-drink", "arbitrary", "Choose any option: ", ["tea", "coffee"], nil),
      ("first-drink", "arbitrary", "Choose the first thing that comes to mind: ", ["tea", "coffee"], nil),
      ("star", "semantic", "Choose the star: ", ["Hello", "Sun"], "Sun"),
      ("cool-color", "semantic", "Blue is a cool color and red is a warm color. Choose the cool color: ", ["red", "blue"], "blue"),
      ("shipment", "semantic", "The shipment status is delivered. Choose the matching status: ", ["pending", "delivered"], "delivered"),
      ("birth", "missing-fact", "Which city was I born in: ", ["London", "Paris"], "undetermined"),
      ("coin", "missing-fact", "Which side will my next coin toss land on: ", ["heads", "tails"], "undetermined"),
      ("bare", "bare", "", ["Hello", "Kitty"], nil)
    ] as [(String, String, String, [String], String?)] {
      for reversed in [false, true] {
        let ordered = reversed ? Array(options.reversed()) : options
        result.append(Self(id: "\(id)-\(reversed)", kind: kind, reversed: reversed,
          question: prefix + ordered.joined(separator: " or ") + "?", expected: expected))
      }
    }
    return result
  }
}

private struct MatchedEssayRun {
  let sample: MatchedEssaySample
  let strategy: String
  let iteration: Int

  static var matrix: [Self] {
    let strategies = ["directID", "noteBeforeID", "noteAfterID"]
    var result: [Self] = []
    for iteration in 0..<2 {
      for (index, sample) in MatchedEssaySample.matrix.enumerated() {
        let shift = (index + iteration) % strategies.count
        for offset in strategies.indices {
          result.append(Self(sample: sample, strategy: strategies[(shift + offset) % strategies.count], iteration: iteration))
        }
      }
    }
    return result
  }
}

#if canImport(FoundationModels)
private enum MatchedEssayError: Error { case unavailable, invalidBatch, budget }
#endif
