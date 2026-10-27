import Foundation

/// Failures at the explicitly selected local-model installation boundary.
public enum OracleGLiNERModelError: Error, Sendable, Equatable {
  case unsupportedBuild
  case missingModel
  case invalidFolder
  case modelTooLarge
  case operationInProgress
}

/// Imports a checkpoint into application storage without adding it to the app bundle.
public actor OracleGLiNERModelStore {
  private let directory: URL
  private let loader: @Sendable (URL) async throws -> OracleGLiNERBackend
  private var isImporting = false
  // One-shot handoff after activation. Switching providers still releases the runtime.
  private var preparedBackend: OracleGLiNERBackend?
  private var installationGeneration = 0
  private let diagnostic: OracleGLiNERDiagnosticSink
  private let requiredFiles = ["gliner.json", "tokenizer.json", "tokenizer_config.json", "GLiNERSmall.mlpackage"]

  /// Creates a store in a caller-owned application-support directory.
  public init(
    directory: URL,
    diagnostic: @escaping OracleGLiNERDiagnosticSink = { _ in },
    loader: @escaping @Sendable (URL) async throws -> OracleGLiNERBackend = OracleGLiNERBackend.load(checkpointAt:)
  ) {
    self.directory = directory
    self.loader = loader
    self.diagnostic = diagnostic
  }

  public var isInstalled: Bool {
    requiredFiles.allSatisfy { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
  }

  /// Returns the validated runtime after installation, or loads the installed checkpoint.
  public func loadBackend() async throws -> OracleGLiNERBackend {
    guard !isImporting else { throw OracleGLiNERModelError.operationInProgress }
    guard isInstalled else { throw OracleGLiNERModelError.missingModel }
    let generation = installationGeneration
    let cached = preparedBackend
    preparedBackend = nil
    await diagnostic(cached == nil ? .stage(.runtime) : .runtimeReused)
    try Task.checkCancellation()
    guard !isImporting, generation == installationGeneration, isInstalled else {
      throw OracleGLiNERModelError.operationInProgress
    }
    let backend: OracleGLiNERBackend
    if let cached { backend = cached } else { backend = try await loader(directory) }
    try Task.checkCancellation()
    guard !isImporting, generation == installationGeneration, isInstalled else {
      throw OracleGLiNERModelError.operationInProgress
    }
    return backend
  }

  /// Copies and validates a Files-selected checkpoint before replacing the active installation.
  public func importCheckpoint(from source: URL) async throws {
    try await install(from: source, distribution: nil)
  }

  /// Installs only the licensed, checksum-pinned public distribution.
  public func importDistribution(from source: URL) async throws {
    let url = Bundle.module.url(forResource: "GLiNER-distribution", withExtension: "json")!
    let distribution = try JSONDecoder().decode(OracleGLiNERDistribution.self, from: Data(contentsOf: url))
    try await install(from: source, distribution: distribution)
  }

  private func install(from source: URL, distribution: OracleGLiNERDistribution?) async throws {
    guard !isImporting else { throw OracleGLiNERModelError.operationInProgress }
    guard source.isFileURL, directory.isFileURL, source.standardizedFileURL != directory.standardizedFileURL else {
      throw OracleGLiNERModelError.invalidFolder
    }
    isImporting = true
    defer { isImporting = false }
    #if canImport(Darwin)
    let hasAccess = source.startAccessingSecurityScopedResource()
    defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }
    #endif
    try Task.checkCancellation()
    let manager = FileManager.default
    let parent = directory.deletingLastPathComponent()
    try manager.createDirectory(at: parent, withIntermediateDirectories: true)
    let staging = parent.appendingPathComponent(".import-\(UUID().uuidString)")
    defer { try? manager.removeItem(at: staging) }
    try manager.createDirectory(at: staging, withIntermediateDirectories: false)
    await diagnostic(.stage(.validation))
    var totalBytes = 0
    let notices = ["LICENSE-APACHE-2.0.txt", "LICENSE-MIT-DeBERTa.txt", "MODEL_CARD.md", "CHANGES.md", "distribution.json"]
    let extras = notices.filter { distribution != nil || manager.fileExists(atPath: source.appendingPathComponent($0).path) }
    for name in requiredFiles + extras {
      let file = source.appendingPathComponent(name)
      try validateTree(at: file, totalBytes: &totalBytes)
      try Task.checkCancellation()
      try manager.copyItem(at: file, to: staging.appendingPathComponent(name))
    }
    try distribution?.validate(directory: staging)
    if distribution != nil { await diagnostic(.inventoryVerified) }
    await diagnostic(.stage(.runtime))
    let candidate: OracleGLiNERBackend
    do {
      candidate = try await loader(staging)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      if distribution != nil { throw OracleGLiNERInstallationFailure.capture(error, stage: .runtime) }
      throw error
    }
    try Task.checkCancellation()
    await diagnostic(.stage(.activation))
    try Task.checkCancellation()
    // No suspension while replacing: failure restores the previous installation.
    let backup = parent.appendingPathComponent(".previous-\(UUID().uuidString)")
    let hadPrevious = manager.fileExists(atPath: directory.path)
    if hadPrevious { try manager.moveItem(at: directory, to: backup) }
    do {
      try manager.moveItem(at: staging, to: directory)
    } catch {
      if hadPrevious { try? manager.moveItem(at: backup, to: directory) }
      throw error
    }
    installationGeneration &+= 1
    preparedBackend = candidate
    if hadPrevious { try? manager.removeItem(at: backup) }
    var ownedDirectory = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? ownedDirectory.setResourceValues(values)
    await diagnostic(.activated)
  }

  /// Removes only the installed checkpoint owned by this store.
  public func removeModel() throws {
    guard !isImporting else { throw OracleGLiNERModelError.operationInProgress }
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
    installationGeneration &+= 1
    preparedBackend = nil
  }

  private func validateTree(at url: URL, totalBytes: inout Int) throws {
    let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey])
    guard values.isSymbolicLink != true else { throw OracleGLiNERModelError.invalidFolder }
    if values.isDirectory == true {
      for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
        try Task.checkCancellation()
        try validateTree(at: child, totalBytes: &totalBytes)
      }
    } else {
      guard values.isRegularFile == true, let bytes = values.fileSize else { throw OracleGLiNERModelError.invalidFolder }
      guard bytes <= 256 * 1_024 * 1_024 - totalBytes else { throw OracleGLiNERModelError.modelTooLarge }
      totalBytes += bytes
    }
  }
}
