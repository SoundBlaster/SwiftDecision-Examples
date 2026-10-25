import Foundation
import Testing

#if canImport(FoundationModels)
import FoundationModels
@testable import OracleGame
#endif

struct OracleLongEssayDiagnosticTests {
  @Test
  @available(macOS 13.0, iOS 16.0, *)
  func essayLengthContractRejectsShortAndLongText() throws {
    let regex = try Regex(longEssayPattern)
    for count in [29, 30, 45, 60, 61] {
      let text = Array(repeating: "word", count: count).joined(separator: " ")
      #expect((text.wholeMatch(of: regex) != nil) == (30...60).contains(count))
      #expect(longEssayWordCount(text) == count)
    }
    #expect(LongEssayRun.matrix.count == 96)
    #expect(Set(LongEssayRun.matrix.map { "\($0.strategy)-\($0.sample.id)-\($0.iteration)" }).count == 96)
  }

  #if canImport(FoundationModels)
  @Test(.enabled(if: ProcessInfo.processInfo.environment["ORACLE_LONG_ESSAY"] == "1"))
  @available(macOS 26.0, iOS 26.0, *)
  func measureRequiredThirtyToSixtyWords() async throws {
    guard case .available = AppleIntelligenceOracleBackend.availability else { throw LongEssayError.unavailable }
    let batch = Int(ProcessInfo.processInfo.environment["ORACLE_LONG_ESSAY_BATCH"] ?? "0") ?? -1
    let probe = ProcessInfo.processInfo.environment["ORACLE_LONG_ESSAY_GUIDE_PROBE"] == "1"
    guard probe || (0..<16).contains(batch) else { throw LongEssayError.invalidBatch }
    let runs = probe
      ? [LongEssayRun(sample: MatchedEssaySample.matrix[0], strategy: "guidedEssay", iteration: 0)]
      : Array(LongEssayRun.matrix[(batch * 6)..<(batch * 6 + 6)])
    let batchStart = ContinuousClock.now
    for run in runs {
      guard batchStart.duration(to: .now) < .seconds(40) else { throw LongEssayError.budget }
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
      If briefNote is requested, write a coherent English paragraph of 30 to 60 whitespace-separated words comparing the alternatives and explaining the selection. Fewer than 30 or more than 60 words is invalid. Do not pad with repeated words. For factual tasks use only provided facts; acknowledge missing information. Do not claim random sampling or personal experiences.
      """
      var properties: [DynamicGenerationSchema.Property] = []
      let includesNote = run.strategy != "directID"
      if includesNote {
        let noteSchema: DynamicGenerationSchema
        if run.strategy == "guidedEssay" {
          noteSchema = DynamicGenerationSchema(type: String.self, guides: [.pattern(try Regex(longEssayPattern))])
        } else {
          noteSchema = DynamicGenerationSchema(type: String.self)
        }
        properties.append(.init(name: "briefNote",
          description: "A coherent English paragraph of 30 to 60 words comparing the alternatives and explaining the selection.",
          schema: noteSchema))
      }
      properties.append(.init(name: "selectedOptionID",
        description: "ID of the alternative you select for the task, or undetermined when the necessary information is missing.",
        schema: DynamicGenerationSchema(type: String.self, guides: [.anyOf(["0", "1", "undetermined"])])))
      let schema = try GenerationSchema(root: DynamicGenerationSchema(name: "TaskSelection", properties: properties), dependencies: [])
      var row: [String: Any] = [
        "id": "\(probe ? "probe__" : "")\(run.strategy)__\(run.sample.id)__\(run.iteration)",
        "strategy": run.strategy, "sample_id": run.sample.id, "repeat": run.iteration,
        "kind": run.sample.kind, "reversed": run.sample.reversed,
        "question": run.sample.question, "options": plan.options,
        "input": input, "session_instructions": instructions,
        "maximum_response_tokens": 512, "expected": run.sample.expected ?? "unconstrained",
        "length_pattern": run.strategy == "guidedEssay" ? longEssayPattern : "none"
      ]
      let started = ContinuousClock.now
      do {
        let selection = try await essaySelection(input: input, instructions: instructions, schema: schema,
          includesNote: includesNote, maximumResponseTokens: 512)
        let idValid = ["0", "1", "undetermined"].contains(selection.id)
        #expect(idValid)
        row["selected_id"] = selection.id
        row["selected"] = Int(selection.id).flatMap { plan.options.indices.contains($0) ? plan.options[$0] : nil } ?? "undetermined"
        row["outcome"] = "generated"
        var lengthValid = !includesNote
        if let note = selection.note {
          let count = longEssayWordCount(note)
          lengthValid = (30...60).contains(count)
          row["note"] = note
          row["note_words"] = count
          row["unique_words"] = Set(note.lowercased().split(whereSeparator: \.isWhitespace)).count
          row["pattern_matched"] = try note.wholeMatch(of: Regex(longEssayPattern)) != nil
        }
        row["protocol_valid"] = idValid && lengthValid
        if !lengthValid { row["protocol_issue"] = "word_count_out_of_bounds" }
      } catch {
        row["outcome"] = "error"
        row["error_type"] = String(reflecting: type(of: error))
        if #available(macOS 27.0, iOS 27.0, *), let modelError = error as? LanguageModelError {
          switch modelError {
          case let .unsupportedGenerationGuide(context):
            row["error_kind"] = "unsupportedGenerationGuide"
            row["guide_error"] = context.debugDescription
          case .guardrailViolation: row["error_kind"] = "guardrailViolation"
          case .refusal: row["error_kind"] = "refusal"
          default: row["error_kind"] = "otherModelError"
          }
        }
        row["protocol_valid"] = false
      }
      let duration = started.duration(to: .now).components
      row["seconds"] = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
      let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
      print("ORACLE_LONG_ESSAY_ROW " + String(decoding: data, as: UTF8.self))
    }
  }
  #endif
}

// A bounded, ASCII whitespace-word grammar. It constrains length, not truth or prose quality.
private let longEssayPattern = #"[A-Za-z0-9][A-Za-z0-9'.,:;!?()-]*(?: [A-Za-z0-9][A-Za-z0-9'.,:;!?()-]*){29,59}"#
private func longEssayWordCount(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }

private struct LongEssayRun {
  let sample: MatchedEssaySample
  let strategy: String
  let iteration: Int

  static var matrix: [Self] {
    let strategies = ["directID", "instructedEssay"]
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
private enum LongEssayError: Error { case unavailable, invalidBatch, budget }
#endif
