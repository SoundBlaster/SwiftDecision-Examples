import Foundation
import OracleGame
import OracleGLiNER
import SwiftDecision
import Testing

private func fixtureBackend() -> OracleGLiNERBackend {
  OracleGLiNERBackend(backend: ClosureDecisionBackend { _ in
    DecisionPrediction(probabilities: [0.05, 0.95], modelIdentifier: "local-fixture")
  })
}

struct OracleGLiNERTests {
  @Test func unavailableJevSelectionMigratesToOfflineWithoutUsingStoredKey() {
    let name = "OracleGLiNERTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let preferences = OracleInferencePreferences(defaults: defaults)
    preferences.select(.jev)
    #expect(preferences.provider(hasJevKey: true, supportsGLiNER: true, supportsJev: false) == .none)
    #expect(preferences.provider(hasJevKey: true, supportsGLiNER: true, supportsJev: true) == .none)
    preferences.select(.jev)
    #expect(preferences.provider(hasJevKey: true, supportsGLiNER: true, supportsJev: true) == .jev)
    preferences.select(.gliner)
    #expect(preferences.provider(hasJevKey: true, supportsGLiNER: true, supportsJev: false) == .gliner)
  }

  @Test func localProviderDoesNotRequireLegacyPilotOptIn() {
    let name = "OracleGLiNERTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let preferences = OracleInferencePreferences(defaults: defaults)
    #expect(!preferences.isPilotEnabled)
    #expect(preferences.provider(hasJevKey: true, supportsGLiNER: true) == .jev)
    preferences.select(.none)
    #expect(preferences.provider(hasJevKey: true, supportsGLiNER: true) == .none)
    preferences.select(.gliner)
    #expect(preferences.provider(hasJevKey: true, supportsGLiNER: true) == .gliner)
    preferences.isPilotEnabled = true
    preferences.select(.gliner)
    #expect(preferences.provider(hasJevKey: false, supportsGLiNER: true) == .gliner)
    #expect(preferences.provider(hasJevKey: true, supportsGLiNER: false) == .none)
    defaults.set("appleIntelligence", forKey: "com.soundblaster.oracleball.inference-provider")
    #expect(preferences.provider(hasJevKey: true, supportsGLiNER: true) == .none)
  }

  @Test func localFailureDoesNotUseOfflineOrNetworkFallback() async throws {
    let backend = OracleGLiNERBackend(backend: ClosureDecisionBackend { _ in throw URLError(.timedOut) })
    #expect(!backend.supportsTransientFailureFallback)
    let engine = OracleGameEngine(backend: backend, fallbackEnabled: false)
    await #expect(throws: (any Error).self) {
      try await engine.answer(for: OracleRequest(question: "Will this work?", mode: .noul))
    }
  }

  @Test func explicitAlternativesUseOneChoiceRequestWithSeparateCriterion() async throws {
    let recorder = Recorder()
    let backend = OracleGLiNERBackend(backend: ClosureDecisionBackend { prompt in
      await recorder.append(prompt)
      return DecisionPrediction(probabilities: [0.05, 0.95], modelIdentifier: "fixture")
    })
    let engine = OracleGameEngine(backend: backend, fallbackEnabled: false)
    let traced = try await engine.answerWithTrace(for: OracleRequest(question: "Choose the star: Hello or Sun?"))
    guard case let .accepted(answer) = traced.outcome else {
      Issue.record("expected a typed Choice result")
      return
    }
    #expect(answer.mode == .choice)
    #expect(answer.displayText == "Sun")
    #expect(answer.source == .model(identifier: "fastino/gliner2.5-small-v1"))
    let prompts = await recorder.prompts
    #expect(prompts.count == 1)
    #expect(prompts.first?.instructions == "Choose the star")
    #expect(prompts.first?.context == "No additional observations.")
    #expect(prompts.first?.options.map(\.description) == ["Hello", "Sun"])
    #expect(!traced.pipeline.contains { $0.title == "Question type" })
  }

  @Test func bareOrQuestionAlsoBypassesIntentClassification() async throws {
    let recorder = Recorder()
    let backend = OracleGLiNERBackend(backend: ClosureDecisionBackend { prompt in
      await recorder.append(prompt)
      return DecisionPrediction(probabilities: [0.5, 0.5], modelIdentifier: "fixture")
    })
    let engine = OracleGameEngine(backend: backend, fallbackEnabled: false)
    let result = try await engine.answer(for: OracleRequest(question: "Hello or Kitty?"))
    guard case .abstained = result else { Issue.record("expected abstention"); return }
    #expect(await recorder.prompts.count == 1)
  }

  private actor Recorder {
    var prompts: [DecisionPrompt] = []
    func append(_ prompt: DecisionPrompt) { prompts.append(prompt) }
  }
}

struct OracleGLiNERModelStoreTests {
  private actor InstallationEvents {
    private(set) var entries: [OracleGLiNERInstallationEvent] = []
    func record(_ event: OracleGLiNERInstallationEvent) { entries.append(event) }
  }

  private actor LoaderProbe {
    private(set) var calls = 0
    func load(_ directory: URL) throws -> OracleGLiNERBackend {
      calls += 1
      let marker = try String(contentsOf: directory.appendingPathComponent("gliner.json"), encoding: .utf8)
      if marker == "replacement-invalid" { throw OracleGLiNERModelError.invalidFolder }
      return OracleGLiNERBackend(backend: ClosureDecisionBackend { _ in
        DecisionPrediction(probabilities: [0.05, 0.95], modelIdentifier: marker)
      })
    }
  }

  private actor BlockingLoader {
    private(set) var calls = 0
    let started: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation
    private var blocked: CheckedContinuation<Void, Never>?

    init() {
      let stream = AsyncStream<Void>.makeStream()
      started = stream.stream
      signal = stream.continuation
    }

    func load(_ directory: URL) async -> OracleGLiNERBackend {
      calls += 1
      if calls == 2 {
        signal.yield(())
        await withCheckedContinuation { blocked = $0 }
      }
      return fixtureBackend()
    }

    func resume() { blocked?.resume(); blocked = nil }
  }

  private func root() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func checkpoint(in root: URL, name: String) throws -> URL {
    let source = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: source.appendingPathComponent("GLiNERSmall.mlpackage"), withIntermediateDirectories: true)
    for file in ["gliner.json", "tokenizer.json", "tokenizer_config.json", "GLiNERSmall.mlpackage/weights.bin", "unrelated.txt"] {
      try Data(name.utf8).write(to: source.appendingPathComponent(file))
    }
    return source
  }

  @Test func validatesBeforeInstallingCopiesOnlyRequiredFilesAndRemovesOwnedModel() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try checkpoint(in: root, name: "source")
    let installed = root.appendingPathComponent("application-support/active")
    let store = OracleGLiNERModelStore(directory: installed, loader: { _ in fixtureBackend() })
    #expect(await !store.isInstalled)
    await #expect(throws: OracleGLiNERModelError.missingModel) { try await store.loadBackend() }
    try await store.importCheckpoint(from: source)
    #expect(await store.isInstalled)
    #expect(!FileManager.default.fileExists(atPath: installed.appendingPathComponent("unrelated.txt").path))
    try await store.removeModel()
    #expect(await !store.isInstalled)
    #expect(FileManager.default.fileExists(atPath: source.path))
  }

  @Test func failedValidationKeepsPreviousInstallation() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let previous = try checkpoint(in: root, name: "previous")
    let replacement = try checkpoint(in: root, name: "replacement")
    let installed = root.appendingPathComponent("active")
    let store = OracleGLiNERModelStore(directory: installed, loader: { directory in
      if try String(contentsOf: directory.appendingPathComponent("gliner.json"), encoding: .utf8) == "replacement" {
        throw OracleGLiNERModelError.invalidFolder
      }
      return fixtureBackend()
    })
    try await store.importCheckpoint(from: previous)
    await #expect(throws: OracleGLiNERModelError.invalidFolder) { try await store.importCheckpoint(from: replacement) }
    #expect(try String(contentsOf: installed.appendingPathComponent("gliner.json"), encoding: .utf8) == "previous")
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".import-") })
  }

  @Test func rejectsSymlinkBeforeInvokingRuntime() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try checkpoint(in: root, name: "source")
    let link = source.appendingPathComponent("tokenizer.json")
    try FileManager.default.removeItem(at: link)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source.appendingPathComponent("unrelated.txt"))
    let store = OracleGLiNERModelStore(directory: root.appendingPathComponent("active"), loader: { _ in
      Issue.record("runtime must not receive a symlinked checkpoint")
      return fixtureBackend()
    })
    await #expect(throws: OracleGLiNERModelError.invalidFolder) { try await store.importCheckpoint(from: source) }
    #expect(await !store.isInstalled)
  }

  @Test func cancellationDoesNotActivateCandidate() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try checkpoint(in: root, name: "source")
    let store = OracleGLiNERModelStore(directory: root.appendingPathComponent("active"), loader: { _ in fixtureBackend() })
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      try await store.importCheckpoint(from: source)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await !store.isInstalled)
  }

  @Test func preparedRuntimeIsHandedOffOnceAfterActivation() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try checkpoint(in: root, name: "source")
    let probe = LoaderProbe()
    let events = InstallationEvents()
    let store = OracleGLiNERModelStore(directory: root.appendingPathComponent("active"),
                                       diagnostic: { await events.record($0) },
                                       loader: { try await probe.load($0) })
    try await store.importCheckpoint(from: source)
    #expect(await probe.calls == 1)
    _ = try await store.loadBackend()
    #expect(await probe.calls == 1)
    #expect(await events.entries.contains(.runtimeReused))
    _ = try await store.loadBackend()
    #expect(await probe.calls == 2)
  }

  @Test func failedReplacementKeepsPreparedRuntimeAndRemovalInvalidatesIt() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = try checkpoint(in: root, name: "previous")
    let invalid = try checkpoint(in: root, name: "replacement-invalid")
    let replacement = try checkpoint(in: root, name: "replacement")
    let probe = LoaderProbe()
    let store = OracleGLiNERModelStore(directory: root.appendingPathComponent("active"),
                                       loader: { try await probe.load($0) })
    try await store.importCheckpoint(from: original)
    await #expect(throws: OracleGLiNERModelError.invalidFolder) { try await store.importCheckpoint(from: invalid) }
    _ = try await store.loadBackend()
    #expect(await probe.calls == 2)
    try await store.importCheckpoint(from: replacement)
    try await store.removeModel()
    await #expect(throws: OracleGLiNERModelError.missingModel) { try await store.loadBackend() }
    #expect(await probe.calls == 3)
    try await store.importCheckpoint(from: original)
    _ = try await store.loadBackend()
    #expect(await probe.calls == 4)
  }

  @Test func cancellationAfterRuntimePreparationKeepsThePreviousModel() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = try checkpoint(in: root, name: "previous")
    let replacement = try checkpoint(in: root, name: "replacement")
    let probe = LoaderProbe()
    let store = OracleGLiNERModelStore(directory: root.appendingPathComponent("active"), loader: { directory in
      let marker = try String(contentsOf: directory.appendingPathComponent("gliner.json"), encoding: .utf8)
      let backend = try await probe.load(directory)
      if marker == "replacement" { withUnsafeCurrentTask { $0?.cancel() } }
      return backend
    })
    try await store.importCheckpoint(from: original)
    let replacementTask = Task { try await store.importCheckpoint(from: replacement) }
    await #expect(throws: CancellationError.self) { try await replacementTask.value }
    #expect(try String(contentsOf: root.appendingPathComponent("active/gliner.json"), encoding: .utf8) == "previous")
    _ = try await store.loadBackend()
    #expect(await probe.calls == 2)
  }

  @Test func concurrentReplacementDoesNotReturnTheOldRuntime() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = try checkpoint(in: root, name: "previous")
    let replacement = try checkpoint(in: root, name: "replacement")
    let probe = BlockingLoader()
    let store = OracleGLiNERModelStore(directory: root.appendingPathComponent("active"),
                                       loader: { await probe.load($0) })
    try await store.importCheckpoint(from: original)
    _ = try await store.loadBackend() // Consume the one-shot handoff.
    let staleLoad = Task { try await store.loadBackend() }
    var started = probe.started.makeAsyncIterator()
    _ = await started.next()
    try await store.importCheckpoint(from: replacement)
    await probe.resume()
    await #expect(throws: OracleGLiNERModelError.operationInProgress) { try await staleLoad.value }
    _ = try await store.loadBackend()
    #expect(await probe.calls == 3) // The replacement's prepared runtime was retained.
    #expect(try String(contentsOf: root.appendingPathComponent("active/gliner.json"), encoding: .utf8) == "replacement")
  }
}

struct OracleGLiNERLiveTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["ORACLE_GLINER_CHECKPOINT"] != nil,
                 "Opt-in local model test; no inference or model download in ordinary CI."))
  func nativeModelAnswersThroughTheOraclePipeline() async throws {
    let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["ORACLE_GLINER_CHECKPOINT"]))
    let installation = FileManager.default.temporaryDirectory.appendingPathComponent("OracleGLiNERLive-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: installation) }
    let store = OracleGLiNERModelStore(directory: installation)
    if FileManager.default.fileExists(atPath: directory.appendingPathComponent("distribution.json").path) {
      try await store.importDistribution(from: directory)
    } else {
      try await store.importCheckpoint(from: directory)
    }
    #expect(await store.isInstalled)
    let backend = try await store.loadBackend()
    let engine = OracleGameEngine(backend: backend, fallbackEnabled: false)
    let traced = try await engine.answerWithTrace(for: OracleRequest(question: "Choose the star: Hello or Sun?"))
    guard case let .accepted(answer) = traced.outcome else { Issue.record("expected Sun"); return }
    #expect(answer.displayText == "Sun")
    #expect(answer.mode == .choice)
    #expect(!traced.pipeline.contains { $0.title == "Question type" })
    #expect(traced.pipeline.contains { !$0.specificationEvents.isEmpty })
    try await store.removeModel()
    #expect(await !store.isInstalled)
  }
}
