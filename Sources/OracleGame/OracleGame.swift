import Foundation
import SpecificationCore
import SwiftDecision

/// The typed decisions exposed by the Oracle Ball demo and its automatic router.
public enum OracleMode: String, CaseIterable, Hashable, Sendable, Identifiable {
  case automatic = "Automatic"
  case noul = "Noul"
  case choice = "Choice"
  case score = "Score"

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
  public let confidence: Double?
  public let source: OracleAnswerSource

  public init(
    mode: OracleMode,
    displayText: String,
    confidence: Double? = nil,
    source: OracleAnswerSource
  ) {
    self.mode = mode
    self.displayText = displayText
    self.confidence = confidence
    self.source = source
  }
}

public enum OracleOutcome: Hashable, Sendable {
  case accepted(OracleAnswer)
  case fallback(OracleAnswer, reason: String)
  case abstained(reason: String)
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
      if prompt.options.count == 3 {
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
  let operation: AsyncFirstMatchSpec<OracleRoutingContext, OracleOperationSelection>

  init() {
    eligibility = AnyAsyncSpecification { request in
      let question = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
      return !question.isEmpty && question.count <= 500
    }
    let choicePlanIsValid = AnyAsyncSpecification<OracleChoicePlan> { plan in
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
      .addPredicate(
        { context in
          guard context.mode == .automatic else { return false }
          return try await choicePlanIsValid.isSatisfiedBy(context.choicePlan)
        },
        result: OracleOperationSelection(.choice))
      .addPredicate(
        { context in context.mode == .automatic && context.asksForProbability },
        result: OracleOperationSelection(.score))
      .fallback(OracleOperationSelection(.noul))
      .build()
  }
}

private struct OracleEvaluation: Sendable {
  let answer: OracleAnswer?
  let confidence: Double
  let reason: String?
  let isFallback: Bool
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
    guard try await requestPolicy.eligibility.isSatisfiedBy(request) else {
      throw OracleGameError.invalidQuestion
    }
    let question = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
    let choicePlan = OracleChoicePlanner.plan(for: question)
    let routingContext = OracleRoutingContext(
      mode: request.mode,
      choicePlan: choicePlan,
      asksForProbability: OracleChoicePlanner.asksForProbability(question))
    guard var selection = try await requestPolicy.operation.decide(routingContext) else {
      throw OracleGameError.noPolicy
    }
    if selection.operation == .choice {
      selection = OracleOperationSelection(.choice, choicePlan: choicePlan)
    }

    let evaluation = try await evaluate(request, selection: selection)
    guard let routed = try await resolutionPolicy.decide(evaluation) else {
      throw OracleGameError.noPolicy
    }
    switch routed {
    case .accepted:
      guard let answer = evaluation.answer else { throw OracleGameError.invalidAnswer }
      return .accepted(answer)
    case .fallback:
      guard let answer = evaluation.answer else { throw OracleGameError.invalidAnswer }
      return .fallback(answer, reason: evaluation.reason ?? "policy fallback")
    case .abstained:
      return .abstained(reason: evaluation.reason ?? "decision policy abstained")
    }
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
    }
  }

  private func makeEvaluation<Value: Sendable>(
    request: OracleRequest,
    mode: OracleMode? = nil,
    displayText: String?,
    result: DecisionResult<Value>
  ) async throws -> OracleEvaluation {
    switch result.outcome {
    case let .abstained(reason):
      return OracleEvaluation(answer: nil, confidence: result.confidence, reason: reason, isFallback: false)
    case .accepted:
      break
    case .fallback:
      break
    }

    guard let displayText else {
      return OracleEvaluation(answer: nil, confidence: result.confidence, reason: "answer validation failed", isFallback: false)
    }
    let source: OracleAnswerSource = backendIdentifier == "offline-fixture"
      ? .offlineFixture
      : .model(identifier: backendIdentifier)
    let answer = OracleAnswer(
      mode: mode ?? request.mode,
      displayText: displayText,
      confidence: result.confidence,
      source: source)
    guard try await answerValidation.isSatisfiedBy(answer) else {
      return OracleEvaluation(answer: nil, confidence: result.confidence, reason: "answer validation failed", isFallback: false)
    }
    if case let .fallback(_, reason) = result.outcome {
      return OracleEvaluation(answer: answer, confidence: result.confidence, reason: reason, isFallback: true)
    }
    return OracleEvaluation(answer: answer, confidence: result.confidence, reason: nil, isFallback: false)
  }
}
