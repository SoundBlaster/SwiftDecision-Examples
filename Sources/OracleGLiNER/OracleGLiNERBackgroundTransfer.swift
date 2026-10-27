#if DEBUG && os(iOS) && canImport(ZIPFoundation)
import Foundation

/// System-owned transport for the explicit development download. The archive is
/// still untrusted until the caller verifies its pinned size, hash and inventory.
@MainActor
public final class OracleGLiNERBackgroundTransfer {
  public static let identifier = "ru.egormerkushev.oracle.gliner.github.v1"
  public static let shared = OracleGLiNERBackgroundTransfer()
  private static let pendingKey = "oracle.gliner.github.pending.v1"

  private let delegate: Delegate
  private var session: URLSession!
  private var waiter: CheckedContinuation<URL, any Error>?
  private var progressHandler: (@MainActor @Sendable (Double?) -> Void)?
  private var eventWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
  private var eventsFinished = false

  public var hasPendingDownload: Bool { UserDefaults.standard.bool(forKey: Self.pendingKey) }

  private init() {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("OracleGLiNERBackground", isDirectory: true)
    delegate = Delegate(directory: base)
    let events = AsyncStream<Event>.makeStream(bufferingPolicy: .bufferingNewest(64))
    delegate.onEvent = { event in events.continuation.yield(event) }
    let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
    config.isDiscretionary = false
    config.sessionSendsLaunchEvents = true
    config.waitsForConnectivity = true
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    session = URLSession(configuration: config, delegate: delegate, delegateQueue: queue)
    Task { [weak self] in
      for await event in events.stream { self?.receive(event) }
    }
  }

  /// Reattaches to a system transfer or starts/resumes the one pinned archive.
  func download(from url: URL, progress: @escaping @MainActor @Sendable (Double?) -> Void) async throws -> URL {
    guard waiter == nil else { throw OracleGLiNERModelError.operationInProgress }
    delegate.setCancelled(false)
    UserDefaults.standard.set(true, forKey: Self.pendingKey)
    if FileManager.default.fileExists(atPath: delegate.archive.path) { return delegate.archive }
    progressHandler = progress
    return try await withCheckedThrowingContinuation { continuation in
      waiter = continuation
      Task {
        let tasks = await session.allTasks
        guard waiter != nil else { return }
        if delegate.isCancelled {
          receive(.result(.failure(CancellationError())))
          return
        }
        if FileManager.default.fileExists(atPath: delegate.archive.path) {
          receive(.result(.success(delegate.archive)))
        } else if let existing = tasks.first(where: { $0.state != .completed }) as? URLSessionDownloadTask {
          if existing.countOfBytesReceived > 0 {
            progress(min(0.99, Double(existing.countOfBytesReceived) / 69_920_984))
          }
          if existing.state == .suspended { existing.resume() }
        } else {
          eventsFinished = false
          let resume = try? Data(contentsOf: delegate.resumeData)
          try? FileManager.default.removeItem(at: delegate.resumeData)
          let task = resume.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: url)
          task.countOfBytesClientExpectsToReceive = 69_920_984
          task.resume()
        }
      }
    }
  }

  func cancel() {
    UserDefaults.standard.removeObject(forKey: Self.pendingKey)
    delegate.setCancelled(true)
    Task {
      let tasks = await session.allTasks
      for task in tasks { task.cancel() }
      if !tasks.contains(where: { $0.state != .completed }) {
        receive(.result(.failure(CancellationError())))
      }
      try? FileManager.default.removeItem(at: delegate.resumeData)
      try? FileManager.default.removeItem(at: delegate.archive)
    }
  }

  func finish() {
    UserDefaults.standard.removeObject(forKey: Self.pendingKey)
    try? FileManager.default.removeItem(at: delegate.resumeData)
    try? FileManager.default.removeItem(at: delegate.archive)
  }

  /// Called from SwiftUI's background URL-session task after a system relaunch.
  public func handleBackgroundEvents() async {
    if eventsFinished { eventsFinished = false; return }
    let id = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled { continuation.resume() }
        else { eventWaiters[id] = continuation }
      }
    } onCancel: {
      Task { @MainActor in self.eventWaiters.removeValue(forKey: id)?.resume() }
    }
  }

  private func receive(_ event: Event) {
    switch event {
    case let .progress(value): progressHandler?(value)
    case let .result(result):
      progressHandler = nil
      if delegate.isCancelled {
        try? FileManager.default.removeItem(at: delegate.archive)
        waiter?.resume(throwing: CancellationError())
      } else {
        waiter?.resume(with: result)
      }
      waiter = nil
    case .eventsFinished:
      if eventWaiters.isEmpty { eventsFinished = true }
      else {
        let waiters = Array(eventWaiters.values)
        eventWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
      }
    }
  }

  private enum Event: Sendable {
    case progress(Double)
    case result(Result<URL, any Error>)
    case eventsFinished
  }

  private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let archive: URL
    let resumeData: URL
    // Set once before URLSession is created, then immutable for the delegate lifetime.
    var onEvent: (@Sendable (Event) -> Void)?
    private let lock = NSLock()
    private var cancelled = false
    private var oversized = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func setCancelled(_ value: Bool) {
      lock.withLock {
        cancelled = value
        if !value { oversized = false }
      }
    }
    init(directory: URL) {
      archive = directory.appendingPathComponent("model.zip")
      resumeData = directory.appendingPathComponent("resume.data")
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
      guard totalBytesWritten <= 69_920_984 else {
        lock.withLock { oversized = true }
        downloadTask.cancel()
        return
      }
      onEvent?(.progress(min(0.99, Double(totalBytesWritten) / 69_920_984)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
      if fileOffset > 0 { onEvent?(.progress(min(0.99, Double(fileOffset) / 69_920_984))) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
      do {
        guard !isCancelled else { throw CancellationError() }
        guard let response = downloadTask.response as? HTTPURLResponse,
              (response.statusCode == 200 || response.statusCode == 206), response.url?.scheme == "https" else {
          throw URLError(.badServerResponse)
        }
        let manager = FileManager.default
        try manager.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: archive.path) { try manager.removeItem(at: archive) }
        try manager.moveItem(at: location, to: archive)
        try? manager.removeItem(at: resumeData)
        onEvent?(.result(.success(archive)))
      } catch { onEvent?(.result(.failure(error))) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
      guard let error else { return }
      if lock.withLock({ oversized }) {
        onEvent?(.result(.failure(OracleGLiNERModelError.modelTooLarge)))
        return
      }
      if !isCancelled, let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
        try? FileManager.default.createDirectory(at: resumeData.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: resumeData, options: [.atomic, .completeFileProtectionUnlessOpen])
      }
      onEvent?(.result(.failure(error)))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
      onEvent?(.eventsFinished)
    }
  }
}
#endif
