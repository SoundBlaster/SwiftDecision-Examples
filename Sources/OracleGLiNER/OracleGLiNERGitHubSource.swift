#if DEBUG && canImport(ZIPFoundation)
import CryptoKit
import Foundation
import ZIPFoundation

/// Explicit development-only alternative to Apple delivery. Never selected automatically.
@MainActor
@available(macOS 12, *)
public final class OracleGLiNERGitHubSource: OracleGLiNERDownloadSource {
  private var session: URLSession?
  private let diagnostic: OracleGLiNERDiagnosticSink
  private var directory: URL?
  private var isDownloading = false
  private var cancelled = false
  private var backgroundArchiveReadyForCleanup = false
  private let url: URL

  public init(diagnostic: @escaping OracleGLiNERDiagnosticSink = { _ in }) {
    self.diagnostic = diagnostic
    self.url = URL(string: "https://github.com/SoundBlaster/SwiftDecision/releases/download/gliner2.5-small-coreml-int8-v1/gliner2.5-small-coreml-int8-v1.zip")!
  }

  // Internal injection for a bounded local HTTP fixture; shipping callers use the pinned URL.
  init(testURL: URL) {
    self.diagnostic = { _ in }
    self.url = testURL
  }

  public func download(progress: @escaping @MainActor @Sendable (Double?) -> Void) async throws -> URL {
    guard !isDownloading else { throw OracleGLiNERModelError.operationInProgress }
    isDownloading = true
    cancelled = false
    defer { isDownloading = false }
    try await releaseDownloadedFiles()
    await diagnostic(.source(.githubDevelopment))
    await diagnostic(.stage(.download))
    progress(nil)
    await diagnostic(.githubConnecting)
    #if os(iOS)
    var stage: OracleGLiNERInstallationFailure.Stage = .download
    do {
      let archive = try await OracleGLiNERBackgroundTransfer.shared.download(from: url, progress: progress)
      try Task.checkCancellation()
      guard !cancelled else { throw CancellationError() }
      progress(1)
      stage = .files
      await diagnostic(.stage(.files))
      let inventory = try Data(contentsOf: Bundle.module.url(forResource: "GLiNER-distribution", withExtension: "json")!)
      let result = try await OracleGLiNERReleaseArchive.extract(
        at: archive, expectedBytes: 69_920_984,
        expectedSHA256: "ff3de19deb3801b41a35194ebf3aa5f01e07eac630e761030829d8ef585c8248",
        inventory: inventory)
      directory = result
      try Task.checkCancellation()
      guard !cancelled else { throw CancellationError() }
      backgroundArchiveReadyForCleanup = true
      return result
    } catch {
      try? await releaseDownloadedFiles()
      if cancelled || Task.isCancelled || error is CancellationError { throw CancellationError() }
      if stage == .files { OracleGLiNERBackgroundTransfer.shared.finish() }
      throw OracleGLiNERInstallationFailure.capture(error, stage: stage)
    }
    #else
    let stream = AsyncThrowingStream<ReleaseDownloadEvent, any Error>.makeStream()
    let delegate = ReleaseDownloadProgress(continuation: stream.continuation)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForResource = 300
    // Delegate-driven task: completion-handler tasks bypass download callbacks.
    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    self.session = session
    defer { session.invalidateAndCancel(); self.session = nil }
    var stage: OracleGLiNERInstallationFailure.Stage = .download
    do {
      session.downloadTask(with: url).resume()
      var downloaded: (URL, URLResponse)?
      for try await event in stream.stream {
        switch event {
        case let .progress(value): progress(value)
        case .redirect: await diagnostic(.githubRedirect)
        case let .completed(file, response): downloaded = (file, response)
        }
      }
      guard let (archive, response) = downloaded else { throw CancellationError() }
      defer { try? FileManager.default.removeItem(at: archive) }
      try Task.checkCancellation()
      guard !cancelled else { throw CancellationError() }
      if let response = response as? HTTPURLResponse {
        await diagnostic(.githubResponse(response.statusCode))
      }
      guard let response = response as? HTTPURLResponse, response.statusCode == 200,
            response.url?.scheme == "https" else {
        throw URLError(.badServerResponse)
      }
      progress(1)
      stage = .files
      await diagnostic(.stage(.files))
      let inventory = try Data(contentsOf: Bundle.module.url(forResource: "GLiNER-distribution", withExtension: "json")!)
      let result = try await OracleGLiNERReleaseArchive.extract(
        at: archive, expectedBytes: 69_920_984,
        expectedSHA256: "ff3de19deb3801b41a35194ebf3aa5f01e07eac630e761030829d8ef585c8248",
        inventory: inventory)
      directory = result
      try Task.checkCancellation()
      guard !cancelled else { throw CancellationError() }
      return result
    } catch {
      try? await releaseDownloadedFiles()
      if cancelled || Task.isCancelled || error is CancellationError { throw CancellationError() }
      throw OracleGLiNERInstallationFailure.capture(error, stage: stage)
    }
    #endif
  }

  public func cancel() {
    cancelled = true
    #if os(iOS)
    OracleGLiNERBackgroundTransfer.shared.cancel()
    #endif
    session?.invalidateAndCancel()
  }

  public func releaseDownloadedFiles() async throws {
    if let directory, FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
    directory = nil
    #if os(iOS)
    if backgroundArchiveReadyForCleanup {
      OracleGLiNERBackgroundTransfer.shared.finish()
      backgroundArchiveReadyForCleanup = false
    }
    #endif
  }
}

private enum ReleaseDownloadEvent: Sendable {
  case progress(Double)
  case redirect
  case completed(URL, URLResponse)
}

private final class ReleaseDownloadProgress: NSObject, URLSessionDownloadDelegate {
  let continuation: AsyncThrowingStream<ReleaseDownloadEvent, any Error>.Continuation

  init(continuation: AsyncThrowingStream<ReleaseDownloadEvent, any Error>.Continuation) { self.continuation = continuation }

  func urlSession(_ session: URLSession, task: URLSessionTask,
                  willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                  completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
    continuation.yield(.redirect)
    completionHandler(request)
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                  didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                  totalBytesExpectedToWrite: Int64) {
    guard totalBytesWritten <= 69_920_984 else { downloadTask.cancel(); return }
    // GitHub's release response may omit Content-Length; the pinned archive size
    // is also checked after download, before extracting any files.
    continuation.yield(.progress(min(0.99, Double(totalBytesWritten) / 69_920_984)))
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                  didFinishDownloadingTo location: URL) {
    guard let response = downloadTask.response else {
      continuation.finish(throwing: URLError(.badServerResponse)); return
    }
    let owned = FileManager.default.temporaryDirectory.appendingPathComponent("OracleDownload-\(UUID().uuidString)")
    do {
      try FileManager.default.moveItem(at: location, to: owned)
      if case .terminated = continuation.yield(.completed(owned, response)) {
        try? FileManager.default.removeItem(at: owned)
      }
      continuation.finish()
    } catch { continuation.finish(throwing: error) }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
    if let error { continuation.finish(throwing: error) }
  }
}

/// Only the pinned archive is parsed; extracted files must also match the pinned inventory.
enum OracleGLiNERReleaseArchive {
  @concurrent
  static func extract(at archiveURL: URL, expectedBytes: Int, expectedSHA256: String,
                      inventory: Data) async throws -> URL {
    try Task.checkCancellation()
    let values = try archiveURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
    guard values.fileSize == expectedBytes, values.isRegularFile == true, values.isSymbolicLink != true else {
      throw OracleGLiNERModelError.invalidFolder
    }
    let digest = SHA256.hash(data: try Data(contentsOf: archiveURL, options: .mappedIfSafe))
      .map { String(format: "%02x", $0) }.joined()
    guard digest == expectedSHA256 else { throw OracleGLiNERModelError.invalidFolder }
    let manifest = try JSONDecoder().decode(OracleGLiNERDistribution.self, from: inventory)
    let archive = try Archive(url: archiveURL, accessMode: .read)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OracleGitHub-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    var completed = false
    defer { if !completed { try? FileManager.default.removeItem(at: root) } }
    for file in manifest.files {
      try Task.checkCancellation()
      guard !file.path.isEmpty, !file.path.hasPrefix("/"),
            !file.path.split(separator: "/").contains(".."),
            let entry = archive["GLiNERSmall/" + file.path], entry.type == .file,
            entry.uncompressedSize == file.bytes else { throw OracleGLiNERModelError.invalidFolder }
      let target = root.appendingPathComponent(file.path)
      try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      _ = try archive.extract(entry, to: target)
    }
    try inventory.write(to: root.appendingPathComponent("distribution.json"), options: .atomic)
    try manifest.validate(directory: root)
    try Task.checkCancellation()
    completed = true
    return root
  }
}
#endif
