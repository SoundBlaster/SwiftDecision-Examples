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

  public init(diagnostic: @escaping OracleGLiNERDiagnosticSink = { _ in }) {
    self.diagnostic = diagnostic
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
    let stream = AsyncStream<ReleaseDownloadEvent>.makeStream()
    let observer = Task {
      for await event in stream.stream {
        switch event {
        case let .progress(value): progress(value)
        case .redirect: await diagnostic(.githubRedirect)
        }
      }
    }
    defer { stream.continuation.finish(); observer.cancel() }
    let delegate = ReleaseDownloadProgress(continuation: stream.continuation)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForResource = 300
    // A session delegate receives download-task progress callbacks. The async
    // download convenience API uses its own completion machinery and did not
    // deliver didWriteData on device.
    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    self.session = session
    defer { session.invalidateAndCancel(); self.session = nil }
    let url = URL(string: "https://github.com/SoundBlaster/SwiftDecision/releases/download/gliner2.5-small-coreml-int8-v1/gliner2.5-small-coreml-int8-v1.zip")!
    var stage: OracleGLiNERInstallationFailure.Stage = .download
    do {
      let (archive, response) = try await downloadArchive(from: url, session: session)
      defer { try? FileManager.default.removeItem(at: archive) }
      stream.continuation.finish()
      await observer.value
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
  }

  public func cancel() {
    cancelled = true
    session?.invalidateAndCancel()
  }

  private func downloadArchive(from url: URL, session: URLSession) async throws -> (URL, URLResponse) {
    try await withCheckedThrowingContinuation { continuation in
      session.downloadTask(with: url) { temporary, response, error in
        if let error { continuation.resume(throwing: error); return }
        guard let temporary, let response else {
          continuation.resume(throwing: URLError(.badServerResponse)); return
        }
        // URLSession removes its temporary file as soon as this callback returns.
        let owned = FileManager.default.temporaryDirectory.appendingPathComponent("OracleDownload-\(UUID().uuidString)")
        do {
          try FileManager.default.moveItem(at: temporary, to: owned)
          continuation.resume(returning: (owned, response))
        } catch { continuation.resume(throwing: error) }
      }.resume()
    }
  }

  public func releaseDownloadedFiles() async throws {
    if let directory, FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
    directory = nil
  }
}

private enum ReleaseDownloadEvent: Sendable {
  case progress(Double)
  case redirect
}

private final class ReleaseDownloadProgress: NSObject, URLSessionDownloadDelegate {
  let continuation: AsyncStream<ReleaseDownloadEvent>.Continuation

  init(continuation: AsyncStream<ReleaseDownloadEvent>.Continuation) { self.continuation = continuation }

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
                  didFinishDownloadingTo location: URL) {}
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
