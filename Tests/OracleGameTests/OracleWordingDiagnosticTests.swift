import Foundation
import Testing

#if canImport(FoundationModels)
import FoundationModels
import OracleGame
import SwiftDecision
#endif

/// Fixed synthetic questions only. No production routing or generation settings are changed.
struct OracleWordingDiagnosticTests {
  @Test
  func wordingMatrixHasBalancedOrdersAndRepeats() {
    let samples = WordingSample.matrix
    #expect(samples.count == 48)
    #expect(WordingSample.controls.count == 6)
    #expect(WordingSample.legacyMatrix.count == 48)
    #expect(WordingSample.legacyControls.count == 6)
    #expect(WordingSample.matrix.allSatisfy { $0.question.unicodeScalars.allSatisfy { $0.value < 128 } })
    #expect(WordingSample.controls.allSatisfy { $0.question.unicodeScalars.allSatisfy { $0.value < 128 } })
    #expect(WordingSample.ablationMatrix.count == 48)
    #expect(Set(samples.map(\.id)).count == 48)
    for group in Dictionary(grouping: samples, by: { "\($0.pair)-\($0.wording)" }).values {
      #expect(group.filter { $0.reversed }.count == group.filter { !$0.reversed }.count)
      #expect(Set(group.map(\.question)).count == 2)
    }
  }

  #if canImport(FoundationModels)
  @Test(.enabled(if: ProcessInfo.processInfo.environment["ORACLE_WORDING_DIAGNOSTIC"] == "1"))
  @available(macOS 26.0, iOS 26.0, *)
  func measureSixApplicationQuestions() async throws {
    guard case .available = AppleIntelligenceOracleBackend.availability else {
      throw WordingDiagnosticError.unavailable
    }
    let batch = Int(ProcessInfo.processInfo.environment["ORACLE_WORDING_BATCH"] ?? "0") ?? -1
    let environment = ProcessInfo.processInfo.environment
    let isAblation = environment["ORACLE_WORDING_PHASE"] == "ablation"
    let legacy = environment["ORACLE_WORDING_LANGUAGE"] == "legacyRussian"
    guard !isAblation || !legacy else { throw WordingDiagnosticError.invalidBatch }
    let matrix: [(WordingSample, WordingInstructionProfile)]
    if isAblation {
      matrix = WordingSample.ablationMatrix
    } else {
      matrix = ((legacy ? WordingSample.legacyMatrix : WordingSample.matrix)
        + (legacy ? WordingSample.legacyControls : WordingSample.controls)).map { ($0, .unchanged) }
    }
    guard batch >= 0, batch * 6 < matrix.count else { throw WordingDiagnosticError.invalidBatch }
    let started = ContinuousClock.now
    for (sample, profile) in matrix[(batch * 6)..<min(batch * 6 + 6, matrix.count)] {
      guard started.duration(to: .now) < .seconds(40) else { throw WordingDiagnosticError.batchBudget }
      let recorder = WordingRecorder()
      let backend = WordingBackend(
        apple: AppleIntelligenceOracleBackend(client: WordingClient(recorder: recorder, profile: profile), timeout: 6),
        recorder: recorder)
      let caseStart = ContinuousClock.now
      var row: [String: Any] = [
        "id": "\(profile.rawValue)__\(sample.id)", "pair": sample.pair, "wording": sample.wording,
        "instruction_profile": profile.rawValue, "language": legacy ? "legacyRussian" : "english",
        "repeat": sample.iteration, "reversed": sample.reversed,
        "question": sample.question, "expected_options": sample.options
      ]
      do {
        let result = try await OracleGameEngine(backend: backend, fallbackEnabled: false)
          .answerWithTrace(for: OracleRequest(question: sample.question))
        #expect(!result.pipeline.contains { $0.id == "Question type" })
        switch result.outcome {
        case let .accepted(answer):
          row["outcome"] = "accepted"
          row["selected"] = answer.displayText
        case .abstained:
          row["outcome"] = "abstained"
        case .fallback:
          row["outcome"] = "fallback"
          Issue.record("Apple experiment must never switch to a fallback")
        }
      } catch {
        // Diagnostic completion is not a quality pass. Count and report every error separately.
        row["outcome"] = "error"
        row["error_type"] = String(reflecting: type(of: error))
        if case let DecisionError.invalidPrediction(reason) = error { row["invalid_prediction_reason"] = reason }
      }
      let snapshot = await recorder.snapshot()
      #expect(snapshot.options == sample.options)
      row["task"] = snapshot.task
      row["context"] = snapshot.context
      row["probabilities"] = snapshot.probabilities
      row["passes"] = snapshot.passes.map {
        ["input": $0.input, "weights": $0.weights,
         "session_instructions": $0.instructions, "field_descriptions": $0.descriptions] as [String: Any]
      }
      let duration = caseStart.duration(to: .now).components
      row["seconds"] = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
      let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
      print("ORACLE_WORDING_ROW " + String(decoding: data, as: UTF8.self))
    }
  }
  #endif
}

private struct WordingSample {
  let id: String
  let pair: String
  let wording: String
  let iteration: Int
  let reversed: Bool
  let question: String
  let options: [String]

  static var matrix: [Self] {
    let prefixes = [
      "bare": "", "any": "Choose any option: ",
      "first": "Choose the first thing that comes to mind: ",
      "preference": "Which do you prefer: ",
      "must": "You must choose exactly one option, even without a reason: ",
      "criterion": "Choose the cool color: "
    ]
    return legacyMatrix.map { sample in
      let words = sample.pair == "colors" ? ["red", "blue"] : ["Hello", "Kitty"]
      let options = sample.reversed ? Array(words.reversed()) : words
      return Self(id: "en-" + sample.id, pair: sample.pair, wording: sample.wording,
        iteration: sample.iteration, reversed: sample.reversed,
        question: prefixes[sample.wording]! + options.joined(separator: " or ") + "?", options: options)
    }
  }

  static var controls: [Self] {
    var result: [Self] = []
    for (pair, prefix, words) in [
      ("facts-en", "Blue is a cool color and red is a warm color. Choose the cool color: ", ["red", "blue"]),
      ("sun", "Choose the star: ", ["Hello", "Sun"]),
      ("farewell", "Choose a farewell: ", ["Hello", "Goodbye"])
    ] {
      for reversed in [false, true] {
        let options = reversed ? Array(words.reversed()) : words
        result.append(Self(id: "en-control-\(pair)-\(reversed)", pair: pair, wording: "control",
          iteration: 0, reversed: reversed,
          question: prefix + options.joined(separator: " or ") + "?", options: options))
      }
    }
    return result
  }

  static var ablationMatrix: [(Self, WordingInstructionProfile)] {
    let samples = matrix.filter { ["any", "first"].contains($0.wording) && $0.iteration < 2 }
    return [WordingInstructionProfile.systemRemoved, .schemaRemoved, .bothRemoved]
      .flatMap { profile in samples.map { ($0, profile) } }
  }

  static var legacyControls: [Self] {
    var result: [Self] = []
    for (pair, prefix, words, separator) in [
      ("facts-ru", "Синий — холодный цвет, красный — тёплый. Выбери холодный цвет: ", ["красный", "синий"], " или "),
      ("facts-en", "Blue is a cool color and red is a warm color. Choose the cool color: ", ["red", "blue"], " or "),
      ("sun", "Choose the star: ", ["Hello", "Sun"], " or ")
    ] {
      for reversed in [false, true] {
        let options = reversed ? Array(words.reversed()) : words
        result.append(Self(id: "control-\(pair)-\(reversed)", pair: pair, wording: "control",
          iteration: 0, reversed: reversed,
          question: prefix + options.joined(separator: separator) + "?", options: options))
      }
    }
    return result
  }

  static var legacyMatrix: [Self] {
    let prefixes = [
      ("bare", ""),
      ("any", "Выбери любой вариант: "),
      ("first", "Выбери первое, что придёт на ум: "),
      ("preference", "Что тебе больше нравится: "),
      ("must", "Обязательно выбери ровно один вариант, даже без оснований: "),
      ("criterion", "Выбери холодный цвет: ")
    ]
    var result: [Self] = []
    for (pair, words, repetitions, forms) in [
      ("colors", ["красный", "синий"], 3, prefixes),
      ("hello", ["Hello", "Kitty"], 2, Array(prefixes.prefix(3)))
    ] {
      for iteration in 0..<repetitions {
        for (index, form) in forms.enumerated() {
          // Alternate first order across formulations and repeats; every pair is tested both ways.
          for reversed in [(iteration + index).isMultiple(of: 2), !(iteration + index).isMultiple(of: 2)] {
            let options = reversed ? Array(words.reversed()) : words
            result.append(Self(
              id: "\(pair)-\(form.0)-\(iteration)-\(reversed ? "reverse" : "forward")",
              pair: pair, wording: form.0, iteration: iteration, reversed: reversed,
              question: form.1 + options.joined(separator: " или ") + "?", options: options))
          }
        }
      }
    }
    return result
  }
}

private enum WordingInstructionProfile: String, Sendable {
  case unchanged, systemRemoved, schemaRemoved, bothRemoved
}

#if canImport(FoundationModels)
private enum WordingDiagnosticError: Error { case unavailable, invalidBatch, batchBudget, unexpectedRoute }

private actor WordingRecorder {
  struct Pass: Sendable {
    let input: String; let weights: [Double]; let instructions: String; let descriptions: [String]
  }
  struct Snapshot: Sendable {
    var task = ""
    var context = ""
    var options: [String] = []
    var probabilities: [Double] = []
    var passes: [Pass] = []
  }
  private var value = Snapshot()
  func input(_ prompt: DecisionPrompt) {
    value.task = prompt.instructions
    value.context = prompt.context
    value.options = prompt.options.map(\.description)
  }
  func prediction(_ values: [Double]) { value.probabilities = values }
  func pass(input: String, weights: [Double], instructions: String, descriptions: [String]) {
    value.passes.append(Pass(input: input, weights: weights, instructions: instructions, descriptions: descriptions))
  }
  func snapshot() -> Snapshot { value }
}

@available(macOS 26.0, iOS 26.0, *)
private struct WordingClient: FoundationModelsDecisionClient {
  let recorder: WordingRecorder
  let profile: WordingInstructionProfile
  func generate(_ request: FoundationModelsDecisionRequest) async throws -> GeneratedContent {
    try Task.checkCancellation()
    var instructions = request.instructions
    if profile == .systemRemoved || profile == .bothRemoved {
      instructions = instructions.replacingOccurrences(
        of: "If no selection criterion is provided or the information is insufficient, indicate uncertainty.",
        with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let alternatives = request.prompt.components(separatedBy: "Alternatives:\n").last!
      .components(separatedBy: "\n").map { String($0.dropFirst(3)) }
    guard alternatives.count == 2 else { throw WordingDiagnosticError.unexpectedRoute }
    let removeSchemaClause = profile == .schemaRemoved || profile == .bothRemoved
    let descriptions = alternatives.map {
      "Relative support for \($0) satisfying the task. 0 means contradicted; 1 means fully supported."
        + (removeSchemaClause ? "" : " Use equal positive support when no criterion is given.")
    }
    let schema: GenerationSchema
    if removeSchemaClause {
      schema = try GenerationSchema(root: DynamicGenerationSchema(name: "DecisionEvaluation",
        properties: descriptions.enumerated().map { index, description in
          .init(name: "option_\(index)", description: description,
            schema: DynamicGenerationSchema(type: Double.self, guides: [.range(0...1)]))
        }), dependencies: [])
    } else {
      schema = request.schema
    }
    let session = LanguageModelSession(model: .default, instructions: instructions)
    let response = try await session.respond(
      to: request.prompt, schema: schema, options: GenerationOptions(samplingMode: .greedy))
    try Task.checkCancellation()
    let weights = try (0..<2).map { try response.content.value(Double.self, forProperty: "option_\($0)") }
    await recorder.pass(input: request.prompt, weights: weights, instructions: instructions, descriptions: descriptions)
    return response.content
  }
}

@available(macOS 26.0, iOS 26.0, *)
private struct WordingBackend: OracleBackendMetadata {
  let apple: AppleIntelligenceOracleBackend
  let recorder: WordingRecorder
  var modelIdentifier: String { apple.modelIdentifier }
  var maximumResponseTime: TimeInterval? { apple.maximumResponseTime }
  func predict(for prompt: DecisionPrompt) async throws -> DecisionPrediction {
    await recorder.input(prompt)
    guard prompt.kind == .choice, prompt.options.count == 2 else { throw WordingDiagnosticError.unexpectedRoute }
    let result = try await apple.predict(for: prompt)
    await recorder.prediction(result.probabilities)
    return result
  }
}
#endif
