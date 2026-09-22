import Foundation
import SpecificationCore
import SwiftDecision

/// The three typed decisions exposed by the Oracle Ball demo.
public enum OracleMode: String, CaseIterable, Hashable, Sendable, Identifiable {
  case noul = "Noul"
  case choice = "Choice"
  case score = "Score"

  public var id: Self { self }
}

/// A request submitted to the oracle engine.
public struct OracleRequest: Hashable, Sendable {
  public let question: String
  public let mode: OracleMode

  public init(question: String, mode: OracleMode) {
    self.question = question
    self.mode = mode
  }
}

public enum OracleAnswerSource: Hashable, Sendable {
  case model(identifier: String)
  case offlineFixture
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
public struct OfflineOracleBackend: DecisionBackend {
  public init() {}

  public func predict(for prompt: DecisionPrompt) async throws -> DecisionPrediction {
    let probabilities: [Double]
    switch prompt.kind {
    case .noul:
      probabilities = [0.13, 0.87]
    case .choice:
      probabilities = [0.12, 0.76, 0.12]
    case .score:
      probabilities = [0.03, 0.08, 0.14, 0.75]
    }
    return DecisionPrediction(probabilities: probabilities, modelIdentifier: "offline-fixture")
  }
}

private enum OracleOperation: Sendable {
  case noul
  case choice
  case score
}

private struct OracleRequestPolicy {
  let eligibility: AnyAsyncSpecification<OracleRequest>
  let operation: AsyncFirstMatchSpec<OracleMode, OracleOperation>

  init() {
    eligibility = AnyAsyncSpecification { request in
      let question = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
      return !question.isEmpty && question.count <= 500
    }
    operation = AsyncFirstMatchSpec<OracleMode, OracleOperation>.builder()
      .addPredicate({ $0 == .noul }, result: .noul)
      .addPredicate({ $0 == .choice }, result: .choice)
      .addPredicate({ $0 == .score }, result: .score)
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

  public init(
    backend: some DecisionBackend = OfflineOracleBackend(),
    configuration: DecisionEngine.Configuration = .init()
  ) {
    decisionEngine = DecisionEngine(backend: backend, configuration: configuration)
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
    guard let operation = try await requestPolicy.operation.decide(request.mode) else {
      throw OracleGameError.noPolicy
    }

    let evaluation = try await evaluate(request, operation: operation)
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
    operation: OracleOperation
  ) async throws -> OracleEvaluation {
    let question = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
    switch operation {
    case .noul:
      let result = try await decisionEngine.noul(
        statement: question,
        context: question,
        fallback: true
      )
      return try await makeEvaluation(
        request: request,
        displayText: result.value.map { $0 ? "Definitely\nyes" : "Probably\nno" },
        result: result
      )
    case .choice:
      let result = try await decisionEngine.choice(
        instructions: question,
        context: question,
        options: [
          ChoiceOption(label: "yes", description: "Definitely yes"),
          ChoiceOption(label: "later", description: "Ask again later"),
          ChoiceOption(label: "no", description: "Probably no"),
        ],
        fallback: "later"
      )
      return try await makeEvaluation(
        request: request,
        displayText: result.value.map {
          switch $0 {
          case "yes": "Definitely\nyes"
          case "no": "Probably\nno"
          default: "Ask again\nlater"
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
        fallback: ScoreValue(level: 1, expectedValue: 0.50)
      )
      let text = result.value.map { "\(Int(($0.expectedValue * 100).rounded()))%" }
      return try await makeEvaluation(request: request, displayText: text, result: result)
    }
  }

  private func makeEvaluation<Value: Sendable>(
    request: OracleRequest,
    displayText: String?,
    result: DecisionResult<Value>
  ) async throws -> OracleEvaluation {
    let source: OracleAnswerSource = result.trace.contains {
      $0.detail == "offline-fixture"
    } ? .offlineFixture : .model(identifier: "SwiftDecision")
    let answer = displayText.map {
      OracleAnswer(mode: request.mode, displayText: $0, confidence: result.confidence, source: source)
    }
    if let answer, try await answerValidation.isSatisfiedBy(answer) {
      switch result.outcome {
      case .accepted:
        return OracleEvaluation(answer: answer, confidence: result.confidence, reason: nil, isFallback: false)
      case let .fallback(_, reason):
        return OracleEvaluation(answer: answer, confidence: result.confidence, reason: reason, isFallback: true)
      case let .abstained(reason):
        return OracleEvaluation(answer: nil, confidence: result.confidence, reason: reason, isFallback: false)
      }
    }
    return OracleEvaluation(answer: nil, confidence: result.confidence, reason: "answer validation failed", isFallback: false)
  }
}
