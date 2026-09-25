import Foundation
import Observation
import OracleGame
import OracleHistory
import SpecificationCore
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
    displayText: OracleAnswerPhrases.random(for: true),
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
    historyStore: OracleHistoryStore? = nil,
    haptics: (any OracleHapticFeedback)? = nil)
  {
    self.credentialsStore = credentialsStore
    let resolvedHistoryStore = historyStore ?? Self.makeHistoryStore()
    self.historyStore = resolvedHistoryStore
    self.haptics = haptics ?? OracleHaptics()
    historyEntries = resolvedHistoryStore.entries
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
      String(localized: "Jev not configured · offline fixture")
    case let .jev(model):
      String(format: String(localized: "Jev configured · live %@"), locale: .current, model)
    }
  }

  var answerStatus: String {
    "\(String(localized: String.LocalizationValue(answer.mode.rawValue))) · \(providerDescription)"
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
    performSubmission(isRandomSimulation: questionIsEmpty(question))
  }

  private func performSubmission(
    isRandomSimulation: Bool,
    playSubmissionHaptic: Bool = true
  ) {
    requestTask?.cancel()
    requestID += 1
    let requestID = requestID
    let request = OracleRequest(question: question, mode: mode)
    let engine = engine
    isSubmitting = true
    statusMessage = nil
    if playSubmissionHaptic { haptics.play(.submit) }

    requestTask = Task { [weak self, engine] in
      do {
        let tracedOutcome: OracleTracedOutcome
        if isRandomSimulation {
          tracedOutcome = try await engine.randomAnswerWithTrace()
        } else {
          tracedOutcome = try await engine.answerWithTrace(for: request)
        }
        guard let self else { return }
        guard self.requestID == requestID else { return }
        switch tracedOutcome.outcome {
        case let .accepted(answer), let .fallback(answer, _):
          self.answer = answer
          self.historyStore.append(
            question: request.question.trimmingCharacters(in: .whitespacesAndNewlines),
            answer: answer,
            pipeline: tracedOutcome.pipeline)
          self.historyEntries = self.historyStore.entries
          self.answerRequestID = requestID
          self.terminalRequestID = 0
          self.statusMessage = isRandomSimulation ? String(localized: "Random answer") : nil
          if answer.mode == .unsupported || answer.noulValue == false {
            self.haptics.play(.negativeResult)
          } else if answer.noulValue == true || answer.mode != .noul {
            self.haptics.play(.positiveResult)
          }
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

  func handleShake() {
    guard questionIsEmpty(question) else {
      submit()
      return
    }

    question = ""
    performSubmission(isRandomSimulation: true, playSubmissionHaptic: false)
  }

  func handleWidgetPrediction() {
    question = ""
    performSubmission(isRandomSimulation: true, playSubmissionHaptic: false)
  }

  func refreshHistory() {
    historyEntries = historyStore.entries
  }

  private static func makeHistoryStore() -> OracleHistoryStore {
    let storageKey = "com.soundblaster.oracleball.question-history"
    guard let sharedDefaults = UserDefaults(suiteName: "group.com.soundblaster.oracleball") else {
      return OracleHistoryStore()
    }

    if sharedDefaults.data(forKey: storageKey) == nil,
       let existingHistory = UserDefaults.standard.data(forKey: storageKey)
    {
      sharedDefaults.set(existingHistory, forKey: storageKey)
    }

    return OracleHistoryStore(defaults: sharedDefaults)
  }

  private func questionIsEmpty(_ question: String) -> Bool {
    let specification = PredicateSpec<String>(description: "Question input is empty") {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return specification.isSatisfiedBy(question)
  }

  func setShakeFeedbackActive(_ isActive: Bool) {
    if isActive {
      haptics.startShakeFeedback()
    } else {
      haptics.stopShakeFeedback()
    }
  }

  func setDragFeedbackActive(_ isActive: Bool) {
    if isActive {
      haptics.startDragFeedback()
    } else {
      haptics.stopDragFeedback()
    }
  }

  func repeatQuestion(_ question: String) {
    self.question = question
    submit()
  }

  func clearQuestionAndAnswer() {
    guard !question.isEmpty || !answer.displayText.isEmpty || isSubmitting else { return }

    haptics.play(.clear)
    requestTask?.cancel()
    requestTask = nil
    requestID += 1
    isSubmitting = false
    question = ""
    answer = OracleAnswer(mode: mode, displayText: "", source: answer.source)
    answerRequestID = requestID
    terminalRequestID = 0
    statusMessage = nil
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
