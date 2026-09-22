import Foundation
import Observation
import OracleGame
import SwiftDecision

@MainActor
@Observable
final class OraclePageModel {
  let engine: OracleGameEngine

  var question = ""
  var mode: OracleMode = .noul
  var answer = OracleAnswer(
    mode: .noul,
    displayText: "Definitely\nyes",
    confidence: 0.87,
    source: .offlineFixture)
  var requestID = 0
  var answerRevision = 0
  var isSubmitting = false
  var statusMessage: String?
  private var requestTask: Task<Void, Never>?

  init(engine: OracleGameEngine = OracleGameEngine()) {
    self.engine = engine
  }

  func submit() {
    requestTask?.cancel()
    requestID += 1
    let requestID = requestID
    let request = OracleRequest(question: question, mode: mode)
    let engine = engine
    isSubmitting = true
    statusMessage = nil

    requestTask = Task { [weak self, engine] in
      do {
        let outcome = try await engine.answer(for: request)
        guard let self else { return }
        guard self.requestID == requestID else { return }
        switch outcome {
        case let .accepted(answer), let .fallback(answer, _):
          self.answer = answer
          self.answerRevision += 1
          self.statusMessage = nil
        case let .abstained(reason):
          self.statusMessage = reason
        }
        self.isSubmitting = false
      } catch is CancellationError {
        guard let self, self.requestID == requestID else { return }
        self.isSubmitting = false
      } catch {
        guard let self, self.requestID == requestID else { return }
        self.statusMessage = error.localizedDescription
        self.isSubmitting = false
      }
    }
  }
}
