import Foundation
import SpecificationCore
import SwiftDecision

/// The typed decisions exposed by the Oracle Ball demo and its automatic router.
public enum OracleMode: String, CaseIterable, Hashable, Sendable, Identifiable {
  case automatic = "Automatic"
  case noul = "Noul"
  case choice = "Choice"
  case score = "Score"
  case unsupported = "Unsupported"

  /// Request modes shown to users. Unsupported is an answer state, not a selectable mode.
  public static let allCases: [OracleMode] = [.automatic, .noul, .choice, .score]

  public var id: Self { self }
}

/// A request submitted to the oracle engine.
public struct OracleRequest: Hashable, Sendable {
  public let question: String
  public let mode: OracleMode

  public init(question: String, mode: OracleMode = .automatic) {
    self.question = question
    self.mode = mode
  }
}

public enum OracleAnswerSource: Hashable, Sendable {
  case model(identifier: String)
  case offlineFixture
}

/// Optional metadata a backend can expose without relying on SwiftDecision traces.
public protocol OracleBackendMetadata: DecisionBackend {
  var modelIdentifier: String { get }
}

/// A display-ready answer. The UI does not need to understand DecisionResult.
public struct OracleAnswer: Hashable, Sendable {
  public let mode: OracleMode
  public let displayText: String
  /// The underlying yes/no decision, when this answer was produced by Noul.
  public let noulValue: Bool?
  public let confidence: Double?
  public let source: OracleAnswerSource

  public init(
    mode: OracleMode,
    displayText: String,
    noulValue: Bool? = nil,
    confidence: Double? = nil,
    source: OracleAnswerSource
  ) {
    self.mode = mode
    self.displayText = displayText
    self.noulValue = noulValue
    self.confidence = confidence
    self.source = source
  }
}

public enum OracleOutcome: Hashable, Sendable {
  case accepted(OracleAnswer)
  case fallback(OracleAnswer, reason: String)
  case abstained(reason: String)
}

/// A content-free snapshot of one important decision stage in an Oracle request.
public struct OraclePipelineStage: Codable, Hashable, Identifiable, Sendable {
  public let id: String
  public let title: String
  public let summary: String?
  public let decisionEvents: [OracleDecisionTraceStep]
  public let specificationEvents: [OracleSpecificationTraceStep]

  public init(
    id: String,
    title: String,
    summary: String? = nil,
    decisionEvents: [OracleDecisionTraceStep] = [],
    specificationEvents: [OracleSpecificationTraceStep] = []
  ) {
    self.id = id
    self.title = title
    self.summary = summary
    self.decisionEvents = decisionEvents
    self.specificationEvents = specificationEvents
  }
}

public struct OracleDecisionTraceStep: Codable, Hashable, Sendable {
  public let stage: String
  public let timestamp: Date
  public let detail: String?

  public init(stage: String, timestamp: Date, detail: String?) {
    self.stage = stage
    self.timestamp = timestamp
    self.detail = detail
  }
}

public struct OracleSpecificationTraceStep: Codable, Hashable, Sendable {
  public let id: Int
  public let parentID: Int?
  public let name: String
  public let outcome: String
  public let durationNanoseconds: UInt64

  public init(
    id: Int,
    parentID: Int?,
    name: String,
    outcome: String,
    durationNanoseconds: UInt64
  ) {
    self.id = id
    self.parentID = parentID
    self.name = name
    self.outcome = outcome
    self.durationNanoseconds = durationNanoseconds
  }
}

/// The answer plus its SpecificationCore and SwiftDecision execution pipeline.
public struct OracleTracedOutcome: Sendable {
  public let outcome: OracleOutcome
  public let pipeline: [OraclePipelineStage]

  public init(outcome: OracleOutcome, pipeline: [OraclePipelineStage]) {
    self.outcome = outcome
    self.pipeline = pipeline
  }
}

public enum OracleGameError: Error, Equatable, Sendable {
  case invalidQuestion
  case invalidAnswer
  case noPolicy
}

/// An offline deterministic backend used by previews, tests, and the demo app.
public struct OfflineOracleBackend: OracleBackendMetadata {
  public let modelIdentifier = "offline-fixture"

  public init() {}

  public func predict(for prompt: DecisionPrompt) async throws -> DecisionPrediction {
    let probabilities: [Double]
    switch prompt.kind {
    case .noul:
      probabilities = [0.13, 0.87]
    case .choice:
      if prompt.instructions == OracleIntentClassifier.instructions,
         prompt.options.count == OracleIntentClassifier.optionCount
      {
        let plan = OracleChoicePlanner.plan(for: prompt.context)
        let index: Int
        if plan.options.count >= 2 {
          index = OracleOperation.choice.classifierIndex
        } else if OracleChoicePlanner.asksForProbability(prompt.context) {
          index = OracleOperation.score.classifierIndex
        } else if OracleQuestionHeuristics.isUnsupported(prompt.context) {
          index = OracleOperation.unsupported.classifierIndex
        } else {
          index = OracleOperation.noul.classifierIndex
        }
        probabilities = (0 ..< OracleIntentClassifier.optionCount).map { $0 == index ? 0.92 : 0.08 / 3 }
      } else if prompt.options.count == 3 {
        probabilities = [0.12, 0.76, 0.12]
      } else {
        let remaining = max(prompt.options.count - 1, 1)
        let secondary = 0.24 / Double(remaining)
        probabilities = prompt.options.indices.map { $0 == 0 ? 0.76 : secondary }
      }
    case .score:
      probabilities = [0.03, 0.08, 0.14, 0.75]
    }
    return DecisionPrediction(probabilities: probabilities, modelIdentifier: modelIdentifier)
  }
}

private enum OracleOperation: Sendable, Equatable {
  case noul
  case choice
  case score
  case unsupported
  case automatic

  var classifierIndex: Int {
    switch self {
    case .noul: 0
    case .choice: 1
    case .score: 2
    case .unsupported: 3
    case .automatic: 0
    }
  }

  var traceLabel: String {
    switch self {
    case .noul: "Noul"
    case .choice: "Choice"
    case .score: "Score"
    case .unsupported: "Unsupported"
    case .automatic: "Automatic"
    }
  }
}

enum OracleQuestionHeuristics {
  static func isUnsupported(_ question: String) -> Bool {
    let normalized = question.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let factualCues = [
      "what is ",
      "what's ",
      "who is ",
      "where is ",
      "when is ",
      "capital of ",
      "define ",
      "how many ",
      "why ",
      "how do ",
      "how can ",
      "explain ",
      "write ",
      "create ",
      "describe ",
      "что такое ",
      "кто такой ",
      "почему ",
      "как ",
      "напиши ",
      "создай ",
      "объясни ",
      "столица ",
    ]
    guard !factualCues.contains(where: normalized.contains) else { return true }
    guard normalized.count >= 4 else { return true }
    return !isBoolean(normalized)
  }

  static func isBoolean(_ question: String) -> Bool {
    let normalized = question.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let booleanCues = [
      "will ", "is ", "are ", "can ", "should ", "do ", "does ", "did ",
      "could ", "would ", "has ", "have ", "may ", "might ", "shall ",
      "am i ", "is it ", "сбудется ли ", "будет ли ", "можно ли ",
      "нужно ли ", "стоит ли ", "правда ли ", "есть ли ", "смогу ли ",
      "получится ли ", "является ли ",
    ]
    return booleanCues.contains(where: normalized.hasPrefix)
  }
}

enum OracleUnsupportedResponses {
  static let messages = [
    "Who knows?",
    "Who can say?",
    "The stars are silent.",
    "The future is unclear.",
    "No clear sign yet.",
    "The answer is hiding.",
    "The universe is undecided.",
  ]

  static func random() -> String {
    messages.randomElement() ?? messages[0]
  }
}

private struct OracleIntentClassifier {
  static let instructions = """
    Classify this question into exactly one intent. Use noul only for a yes/no statement, choice only when the question contains explicit alternatives that can be selected, and score only when it asks for likelihood or probability. Use unsupported for factual, open-ended, malformed, absurd, or otherwise non-Magic-8-Ball questions. Never invent Choice options.
    """
  static let optionCount = 4

  private let engine: DecisionEngine
  private let fallbackEnabled: Bool

  init(engine: DecisionEngine, fallbackEnabled: Bool) {
    self.engine = engine
    self.fallbackEnabled = fallbackEnabled
  }

  fileprivate func classify(_ question: String) async throws -> DecisionResult<OracleOperation> {
    try await engine.choice(
      instructions: Self.instructions,
      context: question,
      options: [
        ChoiceOption(label: .noul, description: "noul: a question that can be answered yes or no"),
        ChoiceOption(label: .choice, description: "choice: select one of the explicit alternatives in the question"),
        ChoiceOption(label: .score, description: "score: estimate likelihood, probability, or confidence"),
        ChoiceOption(label: .unsupported, description: "unsupported: factual, open-ended, malformed, absurd, or not a Magic 8-Ball question"),
      ],
      fallback: fallbackEnabled ? .unsupported : nil)
  }
}

private struct OracleOperationSelection: Sendable {
  let operation: OracleOperation
  let choicePlan: OracleChoicePlan

  init(_ operation: OracleOperation, choicePlan: OracleChoicePlan = OracleChoicePlan(options: [])) {
    self.operation = operation
    self.choicePlan = choicePlan
  }
}

private struct OracleRequestPolicy {
  let eligibility: AnyAsyncSpecification<OracleRequest>
  let choicePlanIsValid: AnyAsyncSpecification<OracleChoicePlan>
  let operation: AsyncFirstMatchSpec<OracleRoutingContext, OracleOperationSelection>

  init() {
    eligibility = AnyAsyncSpecification { request in
      let question = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
      return !question.isEmpty && question.count <= 500
    }
    choicePlanIsValid = AnyAsyncSpecification<OracleChoicePlan> { plan in
      guard (2 ... 5).contains(plan.options.count) else { return false }
      return plan.options.allSatisfy { option in
        let trimmed = option.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1 ... 80).contains(trimmed.count)
      } && Set(plan.options.map { $0.lowercased() }).count == plan.options.count
    }
    operation = AsyncFirstMatchSpec<OracleRoutingContext, OracleOperationSelection>.builder()
      .addPredicate({ $0.mode == .noul }, result: OracleOperationSelection(.noul))
      .addPredicate({ $0.mode == .choice }, result: OracleOperationSelection(.choice))
      .addPredicate({ $0.mode == .score }, result: OracleOperationSelection(.score))
      .addPredicate({ $0.mode == .unsupported }, result: OracleOperationSelection(.unsupported))
      .addPredicate({ $0.mode == .automatic }, result: OracleOperationSelection(.automatic))
      .fallback(OracleOperationSelection(.automatic))
      .build()
  }
}

private struct OracleEvaluation: Sendable {
  let answer: OracleAnswer?
  let confidence: Double
  let reason: String?
  let isFallback: Bool
  let pipeline: [OraclePipelineStage]
}

private enum OracleResolution: Sendable {
  case accepted
  case fallback
  case abstained(reason: String)
}

/// Coordinates SwiftDecision with domain policies expressed as specifications.
/// The engine owns immutable policies and a sendable DecisionEngine. The unchecked
/// conformance is intentional: specifications are immutable after initialization.
public final class OracleGameEngine: @unchecked Sendable {
  private let decisionEngine: DecisionEngine
  private let intentClassifier: OracleIntentClassifier
  private let requestPolicy = OracleRequestPolicy()
  private let answerValidation: AnyAsyncSpecification<OracleAnswer>
  private let resolutionPolicy: AsyncFirstMatchSpec<OracleEvaluation, OracleResolution>
  private let backendIdentifier: String
  private let fallbackEnabled: Bool

  public init(
    backend: some DecisionBackend = OfflineOracleBackend(),
    configuration: DecisionEngine.Configuration = .init(),
    backendIdentifier: String? = nil,
    fallbackEnabled: Bool = true
  ) {
    decisionEngine = DecisionEngine(backend: backend, configuration: configuration)
    self.fallbackEnabled = fallbackEnabled
    intentClassifier = OracleIntentClassifier(
      engine: decisionEngine,
      fallbackEnabled: fallbackEnabled)
    if let backendIdentifier {
      self.backendIdentifier = backendIdentifier
    } else if let metadata = backend as? any OracleBackendMetadata {
      self.backendIdentifier = metadata.modelIdentifier
    } else {
      self.backendIdentifier = String(describing: type(of: backend))
    }
    answerValidation = AnyAsyncSpecification { answer in
      guard !answer.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return false
      }
      guard let confidence = answer.confidence else { return true }
      return confidence.isFinite && (0 ... 1).contains(confidence)
    }
    resolutionPolicy = AsyncFirstMatchSpec<OracleEvaluation, OracleResolution>.builder()
      .addPredicate(
        { evaluation in evaluation.answer != nil && !evaluation.isFallback },
        result: .accepted
      )
      .addPredicate(
        { evaluation in evaluation.answer != nil && evaluation.isFallback },
        result: .fallback
      )
      .addPredicate(
        { evaluation in evaluation.answer == nil },
        result: .abstained(reason: "decision policy abstained")
      )
      .build()
  }

  public func answer(for request: OracleRequest) async throws -> OracleOutcome {
    try await answerWithTrace(for: request).outcome
  }

  public func answerWithTrace(for request: OracleRequest) async throws -> OracleTracedOutcome {
    var pipeline: [OraclePipelineStage] = []
    let eligibilityRecorder = SpecificationTraceRecorder()
    guard try await SpecificationTraceRuntime.evaluateAsync(
      requestPolicy.eligibility,
      request,
      recordingTo: eligibilityRecorder
    ) else {
      throw OracleGameError.invalidQuestion
    }
    pipeline.append(specificationStage("Question eligibility", events: eligibilityRecorder.events))

    let question = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
    let choicePlan = OracleChoicePlanner.plan(for: question)
    let routingContext = OracleRoutingContext(
      mode: request.mode,
      choicePlan: choicePlan,
      asksForProbability: OracleChoicePlanner.asksForProbability(question))
    let routingRecorder = SpecificationTraceRecorder()
    guard var selection = try await SpecificationTraceRuntime.decideAsync(
      requestPolicy.operation,
      routingContext,
      recordingTo: routingRecorder
    ) else {
      throw OracleGameError.noPolicy
    }
    pipeline.append(specificationStage(
      "Request routing",
      events: routingRecorder.events,
      summary: selection.operation.traceLabel))

    let evaluation: OracleEvaluation
    if selection.operation == .unsupported {
      evaluation = try await makeUnsupportedEvaluation(
        confidence: 1,
        reason: "unsupported answer mode requested")
    } else if selection.operation == .automatic {
      let intent = try await intentClassifier.classify(question)
      pipeline.append(decisionStage(
        "Question type",
        result: intent,
        summary: intent.value?.traceLabel))
      guard let operation = intent.value else {
        let reason: String
        if case let .abstained(abstentionReason) = intent.outcome {
          reason = abstentionReason
        } else {
          reason = "intent classifier abstained"
        }
        return OracleTracedOutcome(outcome: .abstained(reason: reason), pipeline: pipeline)
      }

      if operation == .unsupported {
        evaluation = try await makeUnsupportedEvaluation(
          confidence: intent.confidence,
          reason: "question is outside the supported answer types")
      } else if operation == .choice {
        let choiceRecorder = SpecificationTraceRecorder()
        let isValid = try await SpecificationTraceRuntime.evaluateAsync(
          requestPolicy.choicePlanIsValid,
          choicePlan,
          recordingTo: choiceRecorder)
        pipeline.append(specificationStage("Choice alternatives", events: choiceRecorder.events))
        if isValid {
          evaluation = try await evaluate(
            request,
            selection: OracleOperationSelection(.choice, choicePlan: choicePlan))
        } else {
          evaluation = try await makeUnsupportedEvaluation(
            confidence: intent.confidence,
            reason: "choice alternatives could not be extracted")
        }
      } else {
        evaluation = try await evaluate(
          request,
          selection: OracleOperationSelection(operation, choicePlan: choicePlan))
      }
    } else {
      if selection.operation == .choice {
        let choiceRecorder = SpecificationTraceRecorder()
        _ = try await SpecificationTraceRuntime.evaluateAsync(
          requestPolicy.choicePlanIsValid,
          choicePlan,
          recordingTo: choiceRecorder)
        pipeline.append(specificationStage("Choice alternatives", events: choiceRecorder.events))
        selection = OracleOperationSelection(.choice, choicePlan: choicePlan)
      }
      evaluation = try await evaluate(request, selection: selection)
    }

    pipeline.append(contentsOf: evaluation.pipeline)
    let resolutionRecorder = SpecificationTraceRecorder()
    guard let routed = try await SpecificationTraceRuntime.decideAsync(
      resolutionPolicy,
      evaluation,
      recordingTo: resolutionRecorder
    ) else {
      throw OracleGameError.noPolicy
    }
    pipeline.append(specificationStage("Answer resolution", events: resolutionRecorder.events))
    switch routed {
    case .accepted:
      guard let answer = evaluation.answer else { throw OracleGameError.invalidAnswer }
      return OracleTracedOutcome(outcome: .accepted(answer), pipeline: pipeline)
    case .fallback:
      guard let answer = evaluation.answer else { throw OracleGameError.invalidAnswer }
      return OracleTracedOutcome(
        outcome: .fallback(answer, reason: evaluation.reason ?? "policy fallback"),
        pipeline: pipeline)
    case .abstained:
      return OracleTracedOutcome(
        outcome: .abstained(reason: evaluation.reason ?? "decision policy abstained"),
        pipeline: pipeline)
    }
  }

  private func makeUnsupportedEvaluation(
    confidence: Double,
    reason: String
  ) async throws -> OracleEvaluation {
    let source: OracleAnswerSource = backendIdentifier == "offline-fixture"
      ? .offlineFixture
      : .model(identifier: backendIdentifier)
    let answer = OracleAnswer(
      mode: .unsupported,
      displayText: OracleUnsupportedResponses.random(),
      confidence: confidence,
      source: source)
    let validationRecorder = SpecificationTraceRecorder()
    let isValid = try await SpecificationTraceRuntime.evaluateAsync(
      answerValidation,
      answer,
      recordingTo: validationRecorder)
    let validationStage = specificationStage("Answer validation", events: validationRecorder.events)
    guard isValid else {
      return OracleEvaluation(
        answer: nil,
        confidence: confidence,
        reason: "answer validation failed",
        isFallback: false,
        pipeline: [validationStage])
    }
    return OracleEvaluation(
      answer: answer,
      confidence: confidence,
      reason: reason,
      isFallback: true,
      pipeline: [validationStage])
  }

  private func evaluate(
    _ request: OracleRequest,
    selection: OracleOperationSelection
  ) async throws -> OracleEvaluation {
    let question = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
    switch selection.operation {
    case .noul:
      let result = try await decisionEngine.noul(
        statement: question,
        context: question,
        fallback: fallbackEnabled ? true : nil
      )
      return try await makeEvaluation(
        request: request,
        mode: .noul,
        displayText: result.value.map { $0 ? "Definitely\nyes" : "Probably\nno" },
        noulValue: result.value,
        result: result
      )
    case .choice:
      let options = selection.choicePlan.options.isEmpty
        ? ["yes", "later", "no"]
        : selection.choicePlan.options
      let choiceFallback = fallbackEnabled
        ? (options.contains("later") ? "later" : options.first)
        : nil
      let result = try await decisionEngine.choice(
        instructions: question,
        context: question,
        options: options.map { option in
          ChoiceOption(label: option, description: option)
        },
        fallback: choiceFallback
      )
      let isDynamicChoice = !selection.choicePlan.options.isEmpty
      return try await makeEvaluation(
        request: request,
        mode: .choice,
        displayText: result.value.map {
          if isDynamicChoice { return $0 }
          switch $0 {
          case "yes": return "Definitely\nyes"
          case "no": return "Probably\nno"
          default: return "Ask again\nlater"
          }
        },
        result: result
      )
    case .score:
      let result = try await decisionEngine.score(
        instructions: question,
        context: question,
        levels: [
          (description: "Very unlikely", value: 0.25),
          (description: "Uncertain", value: 0.50),
          (description: "Likely", value: 0.75),
          (description: "Very likely", value: 0.90),
        ],
        fallback: fallbackEnabled ? ScoreValue(level: 1, expectedValue: 0.50) : nil
      )
      let text = result.value.map { "\(Int(($0.expectedValue * 100).rounded()))%" }
      return try await makeEvaluation(request: request, mode: .score, displayText: text, result: result)
    case .unsupported, .automatic:
      throw OracleGameError.noPolicy
    }
  }

  private func makeEvaluation<Value: Sendable>(
    request: OracleRequest,
    mode: OracleMode? = nil,
    displayText: String?,
    noulValue: Bool? = nil,
    result: DecisionResult<Value>
  ) async throws -> OracleEvaluation {
    let decisionTraceStage = decisionStage("Answer decision", result: result)
    switch result.outcome {
    case let .abstained(reason):
      return OracleEvaluation(
        answer: nil,
        confidence: result.confidence,
        reason: reason,
        isFallback: false,
        pipeline: [decisionTraceStage])
    case .accepted:
      break
    case .fallback:
      break
    }

    guard let displayText else {
      return OracleEvaluation(
        answer: nil,
        confidence: result.confidence,
        reason: "answer validation failed",
        isFallback: false,
        pipeline: [decisionTraceStage])
    }
    let source: OracleAnswerSource = backendIdentifier == "offline-fixture"
      ? .offlineFixture
      : .model(identifier: backendIdentifier)
    let answer = OracleAnswer(
      mode: mode ?? request.mode,
      displayText: displayText,
      noulValue: noulValue,
      confidence: result.confidence,
      source: source)
    let validationRecorder = SpecificationTraceRecorder()
    let isValid = try await SpecificationTraceRuntime.evaluateAsync(
      answerValidation,
      answer,
      recordingTo: validationRecorder)
    let pipeline = [
      decisionTraceStage,
      specificationStage("Answer validation", events: validationRecorder.events),
    ]
    guard isValid else {
      return OracleEvaluation(
        answer: nil,
        confidence: result.confidence,
        reason: "answer validation failed",
        isFallback: false,
        pipeline: pipeline)
    }
    if case let .fallback(_, reason) = result.outcome {
      return OracleEvaluation(
        answer: answer,
        confidence: result.confidence,
        reason: reason,
        isFallback: true,
        pipeline: pipeline)
    }
    return OracleEvaluation(
      answer: answer,
      confidence: result.confidence,
      reason: nil,
      isFallback: false,
      pipeline: pipeline)
  }

  private func specificationStage(
    _ title: String,
    events: [SpecificationTraceEvent],
    summary: String? = nil
  ) -> OraclePipelineStage {
    OraclePipelineStage(
      id: title,
      title: title,
      summary: summary,
      specificationEvents: events.map { event in
        OracleSpecificationTraceStep(
          id: event.id,
          parentID: event.parentID,
          name: event.name,
          outcome: outcomeName(event.outcome),
          durationNanoseconds: event.durationNanoseconds)
      })
  }

  private func decisionStage<Value: Sendable>(
    _ title: String,
    result: DecisionResult<Value>,
    summary: String? = nil
  ) -> OraclePipelineStage {
    OraclePipelineStage(
      id: title,
      title: title,
      summary: summary,
      decisionEvents: result.trace.map { event in
        OracleDecisionTraceStep(
          stage: event.stage.rawValue,
          timestamp: event.timestamp,
          detail: event.detail)
      },
      specificationEvents: result.specificationTrace.map { event in
        OracleSpecificationTraceStep(
          id: event.id,
          parentID: event.parentID,
          name: event.name,
          outcome: outcomeName(event.outcome),
          durationNanoseconds: event.durationNanoseconds)
      })
  }

  private func outcomeName(_ outcome: SpecificationTraceOutcome) -> String {
    switch outcome {
    case .satisfied: "Satisfied"
    case .unsatisfied: "Not satisfied"
    case .selected: "Selected"
    case .noMatch: "No match"
    case .skipped: "Skipped"
    case let .failed(errorType): "Failed: \(errorType)"
    case .cancelled: "Cancelled"
    }
  }
}
