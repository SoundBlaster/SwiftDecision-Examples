import Foundation

/// Materializes the pinned file set through a transport's file-reading API.
/// Managed asset URLs are a logical namespace, not a caller-owned directory tree.
public actor OracleGLiNERHostedFiles {
  private let inventory: Data
  private var currentDirectory: URL?
  private var isMaterializing = false

  public init() throws {
    let url = Bundle.module.url(forResource: "GLiNER-distribution", withExtension: "json")!
    inventory = try Data(contentsOf: url)
  }

  init(inventory: Data) { self.inventory = inventory }

  public func materialize(
    diagnostic: OracleGLiNERDiagnosticSink = { _ in },
    readFile: @Sendable (String) throws -> Data
  ) async throws -> URL {
    guard !isMaterializing else { throw OracleGLiNERModelError.operationInProgress }
    try removeTemporaryFiles()
    isMaterializing = true
    defer { isMaterializing = false }
    let manifest = try JSONDecoder().decode(OracleGLiNERDistribution.self, from: inventory)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OracleHosted-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    var completed = false
    defer { if !completed { try? FileManager.default.removeItem(at: root) } }
    for file in manifest.files {
      try Task.checkCancellation()
      guard !file.path.isEmpty, !file.path.hasPrefix("/"),
            !file.path.split(separator: "/").contains("..") else {
        throw OracleGLiNERModelError.invalidFolder
      }
      let destination = root.appendingPathComponent(file.path)
      try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      await diagnostic(.fileRequested(path: file.path))
      let bytes = try readFile(file.path)
      guard bytes.count == file.bytes else { throw OracleGLiNERModelError.invalidFolder }
      try bytes.write(to: destination, options: .atomic)
      await diagnostic(.fileRead(path: file.path, bytes: bytes.count))
    }
    try inventory.write(to: root.appendingPathComponent("distribution.json"), options: .atomic)
    try manifest.validate(directory: root)
    completed = true
    currentDirectory = root
    return root
  }

  public func removeTemporaryFiles() throws {
    guard !isMaterializing else { throw OracleGLiNERModelError.operationInProgress }
    guard let currentDirectory else { return }
    if FileManager.default.fileExists(atPath: currentDirectory.path) {
      try FileManager.default.removeItem(at: currentDirectory)
    }
    self.currentDirectory = nil
  }
}
