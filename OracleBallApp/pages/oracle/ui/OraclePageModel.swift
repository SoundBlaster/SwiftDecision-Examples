import Foundation
import Observation
import OracleGame
import OracleHistory
import SwiftDecision

@MainActor
@Observable
final class OraclePageModel {
  private(set) var engine: OracleGameEngine
  private let credentialsStore: OracleCredentialsStore
  private let historyStore: OracleHistoryStore
  private let haptics: any OracleHapticFeedback

  var question = ""
  private(set) var historyEntries: [OracleHistoryEntry]
  var mode: OracleMode = .automatic
  var answer = OracleAnswer(
    mode: .noul,
    displayText: "Definitely\nyes",
    confidence: 0.87,
    source: .offlineFixture)
  var requestID = 0
  var answerRequestID = 0
  var terminalRequestID = 0
  var isSubmitting = false
  var statusMessage: String?
  private var requestTask: Task<Void, Never>?

  enum Provider: Equatable {
    case offline
    case jev(model: String)
  }

  private(set) var provider: Provider

  init(
    engine: OracleGameEngine? = nil,
    credentialsStore: OracleCredentialsStore = OracleCredentialsStore(),
    historyStore: OracleHistoryStore = OracleHistoryStore(),
    haptics: (any OracleHapticFeedback)? = nil)
  {
    self.credentialsStore = credentialsStore
    self.historyStore = historyStore
    self.haptics = haptics ?? OracleHaptics()
    historyEntries = historyStore.entries
    if let engine {
      self.engine = engine
      provider = .offline
      return
    }
    if let key = credentialsStore.readAPIKey(),
       let backend = try? JevOracleBackend(apiKey: key)
    {
      self.engine = OracleGameEngine(backend: backend)
      provider = .jev(model: backend.modelIdentifier)
    } else {
      self.engine = OracleGameEngine()
      provider = .offline
    }
  }

  var configuredAPIKey: String {
    credentialsStore.readAPIKey() ?? ""
  }

  var providerDescription: String {
    switch provider {
    case .offline:
      "Jev not configured · offline fixture"
    case let .jev(model):
      "Jev configured · live \(model)"
    }
  }

  var answerStatus: String {
    "\(answer.mode.rawValue) · \(providerDescription)"
  }

  @discardableResult
  func saveAPIKey(_ input: String) -> Bool {
    requestTask?.cancel()
    requestTask = nil
    requestID += 1
    isSubmitting = false
    let key = input.trimmingCharacters(in: .whitespacesAndNewlines)

    do {
      if key.isEmpty {
        try credentialsStore.deleteAPIKey()
        engine = OracleGameEngine()
        provider = .offline
      } else {
        let backend = try JevOracleBackend(apiKey: key)
        try credentialsStore.saveAPIKey(key)
        engine = OracleGameEngine(backend: backend)
        provider = .jev(model: backend.modelIdentifier)
      }
      statusMessage = nil
      return true
    } catch {
      statusMessage = error.localizedDescription
      return false
    }
  }

  func submit() {
    requestTask?.cancel()
    requestID += 1
    let requestID = requestID
    let request = OracleRequest(question: question, mode: mode)
    let engine = engine
    isSubmitting = true
    statusMessage = nil
    haptics.play(.submit)

    requestTask = Task { [weak self, engine] in
      do {
        let outcome = try await engine.answer(for: request)
        guard let self else { return }
        guard self.requestID == requestID else { return }
        switch outcome {
        case let .accepted(answer), let .fallback(answer, _):
          self.answer = answer
          self.historyStore.append(
            question: request.question.trimmingCharacters(in: .whitespacesAndNewlines),
            answer: answer)
          self.historyEntries = self.historyStore.entries
          self.answerRequestID = requestID
          self.terminalRequestID = 0
          self.statusMessage = nil
          self.haptics.play(
            answer.mode == .unsupported || answer.noulValue == false
              ? .negativeResult : .positiveResult)
        case let .abstained(reason):
          self.terminalRequestID = requestID
          self.statusMessage = reason
        }
        self.isSubmitting = false
      } catch is CancellationError {
        guard let self, self.requestID == requestID else { return }
        self.isSubmitting = false
      } catch {
        guard let self, self.requestID == requestID else { return }
        self.terminalRequestID = requestID
        self.statusMessage = error.localizedDescription
        self.isSubmitting = false
      }
    }
  }

  func repeatQuestion(_ question: String) {
    self.question = question
    submit()
  }

  func deleteHistoryEntry(id: OracleHistoryEntry.ID) {
    historyStore.remove(id: id)
    historyEntries = historyStore.entries
  }

  func clearHistory() {
    historyStore.removeAll()
    historyEntries = historyStore.entries
  }
}
