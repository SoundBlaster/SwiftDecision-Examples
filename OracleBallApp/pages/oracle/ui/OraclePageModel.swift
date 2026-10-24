import Foundation
import Observation
import OracleGame
import OracleHistory
import SpecificationCore
import SwiftDecision

@MainActor
@Observable
final class OraclePageModel {
  private(set) var engine: OracleGameEngine?
  private let preferences: OracleInferencePreferences
  private let credentialsStore: OracleCredentialsStore
  private var historyStore: OracleHistoryStore
  private let usesSharedHistoryStore: Bool
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

  private(set) var provider: OracleInferenceProvider
  private(set) var normalizesAppleOutput: Bool
  private(set) var providerIssue: String?

  init(
    engine: OracleGameEngine? = nil,
    credentialsStore: OracleCredentialsStore = OracleCredentialsStore(),
    historyStore: OracleHistoryStore? = nil,
    preferences: OracleInferencePreferences = OracleInferencePreferences(),
    haptics: (any OracleHapticFeedback)? = nil)
  {
    self.preferences = preferences
    self.credentialsStore = credentialsStore
    normalizesAppleOutput = preferences.normalizesAppleOutput
    provider = preferences.provider(hasJevKey: credentialsStore.readAPIKey() != nil)
    usesSharedHistoryStore = historyStore == nil
    let resolvedHistoryStore = historyStore ?? Self.makeHistoryStore()
    self.historyStore = resolvedHistoryStore
    self.haptics = haptics ?? OracleHaptics()
    historyEntries = resolvedHistoryStore.entries
    if let engine {
      self.engine = engine
      provider = .none
    } else {
      configureProvider()
    }
  }

  var configuredAPIKey: String {
    credentialsStore.readAPIKey() ?? ""
  }

  var providerDescription: String {
    if let providerIssue { return providerIssue }
    switch provider {
    case .none: return String(localized: "None · offline answers")
    case .jev: return String(localized: "Jev · online inference")
    case .appleIntelligence: return String(localized: "Apple Intelligence · on-device inference")
    }
  }

  func selectProvider(_ selection: OracleInferenceProvider) {
    cancelSubmission()
    provider = selection
    preferences.select(selection)
    configureProvider()
    statusMessage = nil
  }

  func setNormalizesAppleOutput(_ enabled: Bool) {
    cancelSubmission()
    normalizesAppleOutput = enabled
    preferences.normalizesAppleOutput = enabled
    configureProvider()
    statusMessage = nil
  }

  func refreshProviderAvailability() {
    guard !isSubmitting, provider == .appleIntelligence else { return }
    configureProvider()
  }

  private func cancelSubmission() {
    requestTask?.cancel()
    requestTask = nil
    requestID += 1
    terminalRequestID = requestID
    isSubmitting = false
  }

  private func configureProvider() {
    engine = nil
    providerIssue = nil
    switch provider {
    case .none:
      engine = OracleGameEngine()
    case .jev:
      guard let key = credentialsStore.readAPIKey(), !key.isEmpty,
            let backend = try? JevOracleBackend(apiKey: key) else {
        providerIssue = String(localized: "Add a Jev API key to use this provider.")
        return
      }
      engine = OracleGameEngine(backend: backend)
    case .appleIntelligence:
      providerIssue = OracleAppleIntelligenceStatus.unavailableMessage
      guard providerIssue == nil else { return }
      engine = OracleGameEngine(
        backend: AppleIntelligenceOracleBackend(normalizeOutput: normalizesAppleOutput),
        fallbackEnabled: false)
    }
  }

  var answerStatus: String {
    "\(String(localized: String.LocalizationValue(answer.mode.rawValue))) · \(providerDescription)"
  }

  @discardableResult
  func saveAPIKey(_ input: String) -> Bool {
    cancelSubmission()
    let key = input.trimmingCharacters(in: .whitespacesAndNewlines)

    do {
      if key.isEmpty {
        try credentialsStore.deleteAPIKey()
      } else {
        _ = try JevOracleBackend(apiKey: key)
        try credentialsStore.saveAPIKey(key)
      }
      configureProvider()
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
    if !isRandomSimulation, provider == .appleIntelligence { configureProvider() }
    guard let engine = isRandomSimulation ? OracleGameEngine() : engine else {
      terminalRequestID = requestID
      isSubmitting = false
      statusMessage = providerIssue
      return
    }
    let submittedProvider = provider
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
          self.statusMessage = isRandomSimulation
            ? String(localized: "Random answer")
            : (submittedProvider == .jev && answer.source == .offlineFixture
              ? String(localized: "Jev unavailable · offline answer used")
              : nil)
          if answer.mode == .unsupported || answer.noulValue == false {
            self.haptics.play(.negativeResult)
          } else if answer.noulValue == true || answer.mode != .noul {
            self.haptics.play(.positiveResult)
          }
        case let .abstained(reason):
          if submittedProvider == .appleIntelligence {
            self.answer = .uncertain(
              mode: request.mode, source: .model(identifier: "apple.foundation-models.on-device"))
            self.historyStore.append(
              question: request.question.trimmingCharacters(in: .whitespacesAndNewlines),
              answer: self.answer, pipeline: tracedOutcome.pipeline)
            self.historyEntries = self.historyStore.entries
            self.answerRequestID = requestID
            self.terminalRequestID = 0
            self.statusMessage = String(localized: "No stable decision. Add a criterion or more context.")
          } else {
            self.terminalRequestID = requestID
            self.statusMessage = reason
          }
        }
        self.isSubmitting = false
      } catch is CancellationError {
        guard let self, self.requestID == requestID else { return }
        self.isSubmitting = false
      } catch {
        guard let self, self.requestID == requestID else { return }
        self.terminalRequestID = requestID
        self.statusMessage = submittedProvider == .appleIntelligence
          ? OracleAppleIntelligenceStatus.failureMessage(for: error)
          : error.localizedDescription
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
    if usesSharedHistoryStore {
      historyStore = Self.makeHistoryStore()
    }
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
    UserDefaults.standard.removeObject(forKey: storageKey)

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

  func stopDragFeedback() {
    haptics.stopDragFeedback()
  }

  func noteDragMovement() {
    haptics.noteDragMovement()
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
