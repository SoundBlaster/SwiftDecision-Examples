import Foundation
import Observation
import OracleGame
import OracleHistory
import OracleGLiNER
import SpecificationCore
import SwiftDecision

@MainActor
@Observable
final class OraclePageModel {
  private(set) var engine: OracleGameEngine
  private let credentialsStore: OracleCredentialsStore
  private var historyStore: OracleHistoryStore
  private let usesSharedHistoryStore: Bool
  private let haptics: any OracleHapticFeedback
  private let preferences: OracleInferencePreferences
  private let modelStore: OracleGLiNERModelStore
  private let usesInjectedEngine: Bool
  private var configurationTask: Task<Void, Never>?
  private var configurationID = 0
  private(set) var isGLiNERPilotEnabled: Bool
  private(set) var isModelInstalled = false
  private(set) var isPreparingModel = false
  private(set) var modelIssue: String?
  private(set) var providerIssue: String?

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
  var supportsGLiNER: Bool { OracleGLiNERBackend.isSupportedBuild }

  init(
    engine: OracleGameEngine? = nil,
    credentialsStore: OracleCredentialsStore = OracleCredentialsStore(),
    historyStore: OracleHistoryStore? = nil,
    haptics: (any OracleHapticFeedback)? = nil,
    preferences: OracleInferencePreferences = OracleInferencePreferences(),
    modelStore: OracleGLiNERModelStore? = nil)
  {
    self.credentialsStore = credentialsStore
    usesSharedHistoryStore = historyStore == nil
    let resolvedHistoryStore = historyStore ?? Self.makeHistoryStore()
    self.historyStore = resolvedHistoryStore
    self.haptics = haptics ?? OracleHaptics()
    self.preferences = preferences
    self.modelStore = modelStore ?? OracleGLiNERModelStore(directory:
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("OracleGLiNER/active", isDirectory: true))
    usesInjectedEngine = engine != nil
    isGLiNERPilotEnabled = preferences.isPilotEnabled
    let selectedProvider = preferences.provider(hasJevKey: credentialsStore.readAPIKey() != nil,
                                               supportsGLiNER: OracleGLiNERBackend.isSupportedBuild)
    provider = selectedProvider
    historyEntries = resolvedHistoryStore.entries
    if let engine {
      self.engine = engine
      provider = .none
      return
    }
    if selectedProvider == .jev, let key = credentialsStore.readAPIKey(),
       let backend = try? JevOracleBackend(apiKey: key)
    {
      self.engine = OracleGameEngine(backend: backend)
    } else {
      self.engine = OracleGameEngine()
      if provider == .gliner { providerIssue = String(localized: "Load a local model to use GLiNER.") }
      else if provider == .jev { providerIssue = String(localized: "Add a Jev API key to use this provider.") }
    }
  }

  var configuredAPIKey: String {
    credentialsStore.readAPIKey() ?? ""
  }

  var providerDescription: String {
    if let providerIssue { return providerIssue }
    switch provider {
    case .none:
      return String(localized: "None · offline simulation")
    case .jev:
      return String(localized: "Jev · online inference")
    case .gliner:
      return String(localized: "GLiNER small · on-device inference")
    }
  }

  var answerStatus: String {
    "\(String(localized: String.LocalizationValue(answer.mode.rawValue))) · \(providerDescription)"
  }

  @discardableResult
  func saveAPIKey(_ input: String) -> Bool {
    let key = input.trimmingCharacters(in: .whitespacesAndNewlines)

    do {
      if key.isEmpty {
        try credentialsStore.deleteAPIKey()
      } else {
        _ = try JevOracleBackend(apiKey: key)
        try credentialsStore.saveAPIKey(key)
      }
      if provider == .jev { selectProvider(.jev) }
      statusMessage = nil
      return true
    } catch {
      statusMessage = error.localizedDescription
      return false
    }
  }

  func prepareProvider() async {
    guard !usesInjectedEngine else { return }
    isModelInstalled = await modelStore.isInstalled
    guard provider == .gliner else { return }
    selectProvider(.gliner)
    await configurationTask?.value
  }

  func selectProvider(_ selection: OracleInferenceProvider) {
    guard !isPreparingModel else { return }
    guard selection != .gliner || (supportsGLiNER && isGLiNERPilotEnabled) else { return }
    cancelPendingSubmission()
    configurationTask?.cancel()
    configurationID += 1
    let token = configurationID
    provider = selection
    preferences.select(selection)
    providerIssue = nil
    // A previous provider's answer must not appear to come from the new one.
    answer = OracleAnswer(mode: mode, displayText: "", source: .offlineFixture)
    answerRequestID = requestID
    terminalRequestID = 0
    engine = OracleGameEngine()
    switch selection {
    case .none: break
    case .jev:
      guard let key = credentialsStore.readAPIKey(), let backend = try? JevOracleBackend(apiKey: key) else {
        providerIssue = String(localized: "Add a Jev API key to use this provider.")
        return
      }
      engine = OracleGameEngine(backend: backend)
    case .gliner:
      providerIssue = String(localized: "Loading local model…")
      isPreparingModel = true
      configurationTask = Task { [weak self] in
        guard let self else { return }
        defer { if self.configurationID == token { self.isPreparingModel = false } }
        do {
          let backend = try await self.modelStore.loadBackend()
          try Task.checkCancellation()
          guard self.configurationID == token, self.provider == .gliner else { return }
          self.engine = OracleGameEngine(backend: backend, fallbackEnabled: false)
          self.providerIssue = nil
          self.modelIssue = nil
        } catch is CancellationError {
          return
        } catch {
          guard self.configurationID == token else { return }
          self.providerIssue = String(localized: "GLiNER is unavailable. Import a compatible model or choose another provider.")
          self.modelIssue = self.providerIssue
        }
      }
    }
  }

  func setGLiNERPilotEnabled(_ enabled: Bool) {
    guard !isPreparingModel else { return }
    isGLiNERPilotEnabled = enabled && supportsGLiNER
    preferences.isPilotEnabled = isGLiNERPilotEnabled
    if !isGLiNERPilotEnabled, provider == .gliner { selectProvider(.none) }
  }

  func importGLiNERModel(from directory: URL) {
    guard !isPreparingModel else { return }
    cancelPendingSubmission()
    isPreparingModel = true
    modelIssue = nil
    configurationTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await self.modelStore.importCheckpoint(from: directory)
        self.isModelInstalled = await self.modelStore.isInstalled
        self.isPreparingModel = false
        self.selectProvider(.gliner)
      } catch {
        self.isPreparingModel = false
        self.modelIssue = String(localized: "Could not import the model. Choose the complete GLiNER small INT8 export folder.")
      }
    }
  }

  func removeGLiNERModel() {
    guard !isPreparingModel else { return }
    if provider == .gliner { selectProvider(.none) }
    isPreparingModel = true
    configurationTask = Task { [weak self] in
      guard let self else { return }
      defer { self.isPreparingModel = false }
      do {
        try await self.modelStore.removeModel()
        self.isModelInstalled = false
        self.modelIssue = nil
      } catch {
        self.modelIssue = String(localized: "Could not remove the local model.")
      }
    }
  }

  func reportModelImportFailure() {
    modelIssue = String(localized: "Could not access the selected model folder.")
  }

  private func cancelPendingSubmission() {
    requestTask?.cancel()
    requestTask = nil
    requestID += 1
    terminalRequestID = requestID
    isSubmitting = false
    statusMessage = nil
  }

  func submit() {
    performSubmission(isRandomSimulation: questionIsEmpty(question))
  }

  private func performSubmission(
    isRandomSimulation: Bool,
    playSubmissionHaptic: Bool = true
  ) {
    guard isRandomSimulation || (!isPreparingModel && providerIssue == nil) else {
      statusMessage = providerIssue ?? String(localized: "Loading local model…")
      return
    }
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
          self.statusMessage = isRandomSimulation
            ? String(localized: "Random answer")
            : (self.provider.isJev && answer.source == .offlineFixture
              ? String(localized: "Jev unavailable · offline answer used")
              : nil)
          if answer.mode == .unsupported || answer.noulValue == false {
            self.haptics.play(.negativeResult)
          } else if answer.noulValue == true || answer.mode != .noul {
            self.haptics.play(.positiveResult)
          }
        case let .abstained(reason):
          if self.provider == .gliner {
            self.answer = OracleAnswer(mode: request.mode, displayText: String(localized: "Not enough\ninformation"),
                                       source: .model(identifier: "fastino/gliner2.5-small-v1"))
            self.historyStore.append(question: request.question.trimmingCharacters(in: .whitespacesAndNewlines),
                                     answer: self.answer, pipeline: tracedOutcome.pipeline)
            self.historyEntries = self.historyStore.entries
            self.answerRequestID = requestID
          }
          self.terminalRequestID = self.provider == .gliner ? 0 : requestID
          self.statusMessage = reason
        }
        self.isSubmitting = false
      } catch is CancellationError {
        guard let self, self.requestID == requestID else { return }
        self.isSubmitting = false
      } catch {
        guard let self, self.requestID == requestID else { return }
        self.terminalRequestID = requestID
        self.statusMessage = self.provider == .gliner
          ? String(localized: "GLiNER could not answer. Try a shorter English question without parentheses or choose another provider.")
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
