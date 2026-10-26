import BackgroundAssets
import Foundation
import OracleGLiNER
import System

/// Apple hosting only. No GitHub or network-provider fallback is implicit.
@MainActor
final class OracleHostedModelDownloader: OracleGLiNERDownloadSource {
  static let assetPackID = "com.soundblaster.oracleball.gliner-small-v1"
  private var currentProgress: Progress?
  private var cancelled = false

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
    if #available(iOS 26.4, *) {
      try await manager.ensureLocalAvailability(of: pack, requireLatestVersion: false)
    } else {
      try await manager.ensureLocalAvailability(of: pack)
    }
    try Task.checkCancellation()
    guard !cancelled else { throw CancellationError() }
    // Resolve one known file; the remaining tree has the same unique pack prefix.
    return try manager.url(for: FilePath("GLiNERSmall/gliner.json")).deletingLastPathComponent()
  }

  func cancel() {
    cancelled = true
    currentProgress?.cancel()
  }

  func releaseDownloadedFiles() async throws {
    try await AssetPackManager.shared.remove(assetPackWithID: Self.assetPackID)
  }
}
