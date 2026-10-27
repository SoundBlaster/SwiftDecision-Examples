import BackgroundAssets
import Foundation
import OracleGLiNER
import OSLog
import System

/// Apple hosting only. No GitHub or network-provider fallback is implicit.
@MainActor
final class OracleHostedModelDownloader: OracleGLiNERDownloadSource {
  static let assetPackID = "gliner-small-v1"
  private var currentProgress: Progress?
  private var cancelled = false
  private var hostedFiles: OracleGLiNERHostedFiles?
  private let diagnostic: OracleGLiNERDiagnosticSink
  private let logger = Logger(subsystem: "ru.egormerkushev.oracle", category: "ModelInstallation")

  init(diagnostic: @escaping OracleGLiNERDiagnosticSink = { _ in }) {
    self.diagnostic = diagnostic
  }

  func download(progress: @escaping @MainActor @Sendable (Double?) -> Void) async throws -> URL {
    cancelled = false
    progress(nil)
    let manager = AssetPackManager.shared
    let updates = Task {
      for await update in manager.statusUpdates(forAssetPackWithID: Self.assetPackID) {
        if Task.isCancelled { break }
        switch update {
        case let .downloading(_, value):
          currentProgress = value
          if cancelled { value.cancel() }
          progress(value.fractionCompleted)
        case .finished:
          progress(1)
        default: break
        }
      }
    }
    defer { updates.cancel(); currentProgress = nil }
    var stage: OracleGLiNERInstallationFailure.Stage = .manifest
    do {
      await diagnostic(.stage(.manifest))
      let pack: AssetPack
      if #available(iOS 27, *) {
        guard let available = try await manager.manifest.assetPack(withID: Self.assetPackID) else {
          throw ManagedBackgroundAssetsError.assetPackNotFound(withID: Self.assetPackID)
        }
        pack = available
      } else {
        pack = try await manager.assetPack(withID: Self.assetPackID)
      }
      try Task.checkCancellation()
      stage = .download
      await diagnostic(.stage(.download))
      if #available(iOS 26.4, *) {
        try await manager.ensureLocalAvailability(of: pack, requireLatestVersion: false)
      } else {
        try await manager.ensureLocalAvailability(of: pack)
      }
      try Task.checkCancellation()
      guard !cancelled else { throw CancellationError() }
      await diagnostic(.downloadAvailable)
      stage = .files
      await diagnostic(.stage(.files))
      let files = try hostedFiles ?? OracleGLiNERHostedFiles()
      hostedFiles = files
      let assetPackID = Self.assetPackID
      return try await files.materialize(diagnostic: diagnostic) { path in
        try manager.contents(at: FilePath("GLiNERSmall/" + path),
                             searchingInAssetPackWithID: assetPackID)
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      let failure = OracleGLiNERInstallationFailure.capture(error, stage: stage)
      logger.error("Model installation failed at \(failure.stage.rawValue, privacy: .public): \(failure.domain, privacy: .public) code \(failure.code)")
      throw failure
    }
  }

  func cancel() {
    cancelled = true
    currentProgress?.cancel()
  }

  func releaseDownloadedFiles() async throws {
    try await hostedFiles?.removeTemporaryFiles()
    try await AssetPackManager.shared.remove(assetPackWithID: Self.assetPackID)
  }
}
