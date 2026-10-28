import Foundation
import Observation
import OracleGame
import OracleHistory
import OracleGLiNER
import SpecificationCore
import SwiftDecision
import UIKit

@MainActor
@Observable
final class OraclePageModel {
  private static let hostedInstallPendingKey = "oracle.gliner.apple.pending.v1"
  private(set) var engine: OracleGameEngine
  private let credentialsStore: OracleCredentialsStore
  private var historyStore: OracleHistoryStore
  private let usesSharedHistoryStore: Bool
  private let haptics: any OracleHapticFeedback
  private let preferences: OracleInferencePreferences
  private let modelStore: OracleGLiNERModelStore
  private let usesInjectedEngine: Bool
  private var configurationTask: Task<Void, Never>?
  let installationLog: OracleModelInstallationLog
  private let modelDownloadSource: any OracleGLiNERDownloadSource
  private var activeModelDownloadSource: (any OracleGLiNERDownloadSource)?
  private(set) var isDownloadingModel = false
  private var previousIdleTimerDisabled: Bool?
  private(set) var modelDownloadProgress: Double?
  private var configurationID = 0
  private(set) var isModelInstalled = false
  private(set) var isPreparingModel = false
  private(set) var modelIssue: String?
  private(set) var providerIssue: String?
  private(set) var glinerMinimumConfidence: Double
  private var loadedGLiNERBackend: OracleGLiNERBackend?

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
  var showsSafetyIntervention = false
  private var requestTask: Task<Void, Never>?

  private(set) var provider: OracleInferenceProvider
  var supportsGLiNER: Bool { OracleGLiNERBackend.isSupportedBuild }

  isolated deinit {
    if let previousIdleTimerDisabled {
      UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
    }
  }

  init(
    engine: OracleGameEngine? = nil,
    credentialsStore: OracleCredentialsStore = OracleCredentialsStore(),
    historyStore: OracleHistoryStore? = nil,
    haptics: (any OracleHapticFeedback)? = nil,
    preferences: OracleInferencePreferences = OracleInferencePreferences(),
    modelStore: OracleGLiNERModelStore? = nil,
    modelDownloadSource: (any OracleGLiNERDownloadSource)? = nil)
  {
    let installationLog = OracleModelInstallationLog()
    self.installationLog = installationLog
    let diagnostic: OracleGLiNERDiagnosticSink = { [weak installationLog] event in
      await installationLog?.record(event)
    }
    self.modelDownloadSource = modelDownloadSource ?? OracleHostedModelDownloader(diagnostic: diagnostic)
    self.credentialsStore = credentialsStore
    usesSharedHistoryStore = historyStore == nil
    let resolvedHistoryStore = historyStore ?? Self.makeHistoryStore()
    self.historyStore = resolvedHistoryStore
    self.haptics = haptics ?? OracleHaptics()
    self.preferences = preferences
    glinerMinimumConfidence = preferences.glinerMinimumConfidence
    self.modelStore = modelStore ?? OracleGLiNERModelStore(directory:
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("OracleGLiNER/active", isDirectory: true), diagnostic: diagnostic)
    usesInjectedEngine = engine != nil
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
    if UserDefaults.standard.bool(forKey: Self.hostedInstallPendingKey) {
      if !isModelInstalled {
        installHostedGLiNERModel()
        await configurationTask?.value
        return
      }
      UserDefaults.standard.removeObject(forKey: Self.hostedInstallPendingKey)
    }
    #if DEBUG
    if OracleGLiNERBackgroundTransfer.shared.hasPendingDownload {
      installDevelopmentGLiNERModel()
      await configurationTask?.value
      return
    }
    #endif
    guard provider == .gliner else { return }
    selectProvider(.gliner)
    await configurationTask?.value
  }

  func selectProvider(_ selection: OracleInferenceProvider) {
    guard !isPreparingModel else { return }
    guard selection != .gliner || supportsGLiNER else { return }
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
    loadedGLiNERBackend = nil
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
          self.loadedGLiNERBackend = backend
          self.updateGLiNERPolicy()
          self.installationLog.record(.providerReady)
          self.providerIssue = nil
          self.modelIssue = nil
        } catch is CancellationError {
          return
        } catch {
          guard self.configurationID == token else { return }
          if self.isModelInstalled {
            self.installationLog.record(.failed(.capture(error, stage: .runtime)))
          }
          self.providerIssue = String(localized: "GLiNER is unavailable. Import a compatible model or choose another provider.")
          self.modelIssue = self.providerIssue
        }
      }
    }
  }

  func setGLiNERMinimumConfidence(_ value: Double) {
    guard value.isFinite, (0 ... 1).contains(value), !isSubmitting else { return }
    glinerMinimumConfidence = value
    preferences.glinerMinimumConfidence = value
    if provider == .gliner { updateGLiNERPolicy() }
  }

  private func updateGLiNERPolicy() {
    guard let backend = loadedGLiNERBackend else { return }
    let policy = DecisionPolicy(minimumConfidence: glinerMinimumConfidence)
    engine = OracleGameEngine(backend: backend, configuration: .init(
      policies: DecisionPolicies(noul: policy, choice: policy, score: policy)), fallbackEnabled: false)
  }

  func installHostedGLiNERModel() {
    guard !isPreparingModel else { return }
    UserDefaults.standard.set(true, forKey: Self.hostedInstallPendingKey)
    installGLiNERModel(from: modelDownloadSource,
      failureMessage: String(localized: "Could not install the Apple-hosted model. Please try again."),
      isHosted: true)
  }

  #if DEBUG
  func installDevelopmentGLiNERModel() {
    let source = OracleGLiNERGitHubSource { [weak installationLog] event in
      await installationLog?.record(event)
    }
    installGLiNERModel(from: source,
      failureMessage: String(localized: "Could not install the GitHub model. Please try again."))
  }
  #endif

  private func installGLiNERModel(from source: any OracleGLiNERDownloadSource, failureMessage: String,
                                  isHosted: Bool = false) {
    guard !isPreparingModel else { return }
    activeModelDownloadSource = source
    cancelPendingSubmission()
    isPreparingModel = true
    setModelDownloading(true)
    modelDownloadProgress = nil
    modelIssue = nil
    installationLog.record(.started(
      version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
      build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))
    configurationTask = Task { [weak self] in
      guard let self else { return }
      defer {
        self.setModelDownloading(false)
        self.activeModelDownloadSource = nil
        if isHosted { UserDefaults.standard.removeObject(forKey: Self.hostedInstallPendingKey) }
      }
      do {
        let installer = OracleGLiNERInstaller(source: source, store: self.modelStore,
          diagnostic: { [weak installationLog = self.installationLog] event in
            await installationLog?.record(event)
          })
        try await installer.install { [weak self] update in
          switch update {
          case let .downloading(value):
            self?.modelDownloadProgress = value
            if let value, value.isFinite {
              self?.installationLog.record(.progress(Int((max(0, min(value, 1)) * 100).rounded())))
            }
          case .validating: self?.setModelDownloading(false)
          }
        }
        self.isModelInstalled = await self.modelStore.isInstalled
        self.installationLog.record(.completed)
        self.isPreparingModel = false
        self.selectProvider(.gliner)
      } catch {
        self.setModelDownloading(false)
        self.isPreparingModel = false
        self.isModelInstalled = await self.modelStore.isInstalled
        if error is CancellationError || Task.isCancelled {
          self.installationLog.record(.cancelled)
        } else {
          self.installationLog.record(.failed(.capture(error, stage: .validation)))
          if let failure = error as? OracleGLiNERInstallationFailure {
            self.modelIssue = failureMessage + " [\(failure.stage.rawValue): \(failure.domain) \(failure.code)]"
          } else {
            self.modelIssue = failureMessage
          }
        }
      }
    }
  }

  func cancelHostedModelInstallation() {
    guard isDownloadingModel else { return }
    activeModelDownloadSource?.cancel()
    configurationTask?.cancel()
  }

  private func setModelDownloading(_ downloading: Bool) {
    if downloading, previousIdleTimerDisabled == nil {
      previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
      UIApplication.shared.isIdleTimerDisabled = true
    } else if !downloading, let previous = previousIdleTimerDisabled {
      UIApplication.shared.isIdleTimerDisabled = previous
      previousIdleTimerDisabled = nil
    }
    isDownloadingModel = downloading
  }

  func importGLiNERModel(from directory: URL) {
    guard !isPreparingModel else { return }
    cancelPendingSubmission()
    modelDownloadProgress = nil
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
    modelDownloadProgress = nil
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
    let usesMissingModelSimulation = OracleMissingModelFallbackSpec().isSatisfiedBy(.init(
      localModelSelected: provider == .gliner,
      modelInstalled: isModelInstalled,
      preparingModel: isPreparingModel))
    let requiresSafetyIntervention = OracleQuestionSafetySpec().decide(question) != nil
    guard requiresSafetyIntervention || isRandomSimulation || usesMissingModelSimulation
      || (!isPreparingModel && providerIssue == nil) else {
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
        if isRandomSimulation || usesMissingModelSimulation {
          tracedOutcome = try await engine.randomAnswerWithTrace(for: request)
        } else {
          tracedOutcome = try await engine.answerWithTrace(for: request, capturingFailures: true)
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
          self.statusMessage = usesMissingModelSimulation
            ? String(localized: "Random answer · without AI")
            : isRandomSimulation
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
        case .safetyIntervention:
          self.answer = OracleAnswer(mode: request.mode, displayText: "", source: .offlineFixture)
          self.answerRequestID = requestID
          self.terminalRequestID = 0
          self.statusMessage = String(localized: "Please seek support")
          self.showsSafetyIntervention = true
        }
        self.isSubmitting = false
      } catch is CancellationError {
        guard let self, self.requestID == requestID else { return }
        if !Task.isCancelled {
          self.recordFailure(OracleTracedFailure(kind: "cancelled", mode: request.mode,
            provider: self.provider.rawValue, pipeline: []), request: request, requestID: requestID)
        }
        self.isSubmitting = false
      } catch {
        guard let self, self.requestID == requestID else { return }
        let failure = (error as? OracleTracedFailure) ?? OracleTracedFailure(
          kind: "requestError", mode: request.mode, provider: self.provider.rawValue, pipeline: [])
        self.recordFailure(failure, request: request, requestID: requestID)
        self.isSubmitting = false
      }
    }
  }

  private func recordFailure(_ failure: OracleTracedFailure, request: OracleRequest, requestID: Int) {
    let message = failure.kind == "timeout"
      ? String(localized: "The model timed out. Please try again.")
      : String(localized: "The model could not answer. Please try again.")
    // Render a status for this request, rather than restoring a previous, possibly empty plate.
    answer = OracleAnswer(mode: failure.mode, displayText: String(localized: "Could not\nanswer"),
                          source: .model(identifier: failure.provider))
    historyStore.appendFailure(question: request.question.trimmingCharacters(in: .whitespacesAndNewlines),
                               failure: failure, message: message)
    historyEntries = historyStore.entries
    answerRequestID = requestID
    terminalRequestID = 0
    statusMessage = message
    haptics.play(.negativeResult)
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
    guard let sharedDefaults = UserDefaults(suiteName: "group.ru.egormerkushev.oracle") else {
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


/// UI-owned persistent journal; only typed, safe technical events reach storage.
@MainActor
@Observable
final class OracleModelInstallationLog {
  private static let key = "oracle.model-installation-log.v1"
  private let defaults: UserDefaults
  private(set) var journal: OracleGLiNERInstallationLog

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    journal = defaults.data(forKey: Self.key)
      .flatMap { try? JSONDecoder().decode(OracleGLiNERInstallationLog.self, from: $0) }
      ?? OracleGLiNERInstallationLog()
  }

  func record(_ event: OracleGLiNERInstallationEvent) {
    let previous = journal.entries.last?.id
    journal.record(event)
    guard journal.entries.last?.id != previous,
          let data = try? JSONEncoder().encode(journal) else { return }
    defaults.set(data, forKey: Self.key)
  }

  func clear() {
    journal.clear()
    defaults.removeObject(forKey: Self.key)
  }
}
