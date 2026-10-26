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
  private let requiredFiles = ["gliner.json", "tokenizer.json", "tokenizer_config.json", "GLiNERSmall.mlpackage"]

  /// Creates a store in a caller-owned application-support directory.
  public init(
    directory: URL,
    loader: @escaping @Sendable (URL) async throws -> OracleGLiNERBackend = OracleGLiNERBackend.load(checkpointAt:)
  ) {
    self.directory = directory
    self.loader = loader
  }

  public var isInstalled: Bool {
    requiredFiles.allSatisfy { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
  }

  /// Returns a new runtime for the installed checkpoint. Errors do not invoke offline inference.
  public func loadBackend() async throws -> OracleGLiNERBackend {
    guard isInstalled else { throw OracleGLiNERModelError.missingModel }
    return try await loader(directory)
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
    _ = try await loader(staging)
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
    if hadPrevious { try? manager.removeItem(at: backup) }
    var ownedDirectory = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? ownedDirectory.setResourceValues(values)
  }

  /// Removes only the installed checkpoint owned by this store.
  public func removeModel() throws {
    guard !isImporting else { throw OracleGLiNERModelError.operationInProgress }
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
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
