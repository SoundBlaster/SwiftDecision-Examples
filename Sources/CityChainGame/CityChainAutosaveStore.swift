import Foundation

/// One versioned save envelope for CityChainApp's current game.
public struct CityChainAutosave: Codable, Sendable, Equatable {
  public static let currentVersion = 2

  public let version: Int
  public let savedAt: Date
  public let game: CityGameFixture

  public init(game: CityGameFixture, savedAt: Date = Date()) {
    version = Self.currentVersion
    self.savedAt = savedAt
    self.game = game
  }

  enum CodingKeys: String, CodingKey { case version, savedAt, game }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedVersion = try container.decode(Int.self, forKey: .version)
    guard decodedVersion == 1 || decodedVersion == Self.currentVersion else {
      throw DecodingError.dataCorruptedError(
        forKey: .version, in: container, debugDescription: "Unsupported autosave version.")
    }
    version = Self.currentVersion
    savedAt = decodedVersion == 1
      ? .distantPast
      : try container.decode(Date.self, forKey: .savedAt)
    game = try container.decode(CityGameFixture.self, forKey: .game)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Self.currentVersion, forKey: .version)
    try container.encode(savedAt, forKey: .savedAt)
    try container.encode(game, forKey: .game)
  }
}

public enum CityChainAutosaveLocation: Sendable, Equatable {
  case iCloudDocuments
  case applicationSupport
}

public enum CityChainCloudReadiness: Sendable, Equatable {
  case ready
  case missing
  case downloadPending
  case unavailable
}

public struct CityChainAutosaveCandidate: Sendable {
  public let save: CityChainAutosave
  public let location: CityChainAutosaveLocation
  public let canPromoteToCloud: Bool

  public init(
    save: CityChainAutosave, location: CityChainAutosaveLocation,
    canPromoteToCloud: Bool = true
  ) {
    self.save = save
    self.location = location
    self.canPromoteToCloud = canPromoteToCloud
  }
}

public enum CityChainAutosaveError: Error, LocalizedError, Sendable {
  case bothLocationsUnavailable(cloud: String, local: String)

  public var errorDescription: String? {
    switch self {
    case .bothLocationsUnavailable(let cloud, let local):
      "Autosave failed. iCloud: \(cloud) Application Support: \(local)"
    }
  }
}

/// Injectable access layer. Cloud calls are coordinated; local calls are direct.
public protocol CityChainAutosaveFileAccess: Sendable {
  func cloudReadiness(at url: URL) -> CityChainCloudReadiness
  func read(from url: URL, coordinate: Bool) throws -> Data
  func write(_ data: Data, to url: URL, coordinate: Bool) throws
  func createDirectory(at url: URL) throws
}

/// Resolves and accesses one autosave file, preferring iCloud Documents.
/// This is an actor so ubiquity lookup and synchronous file operations run off the UI actor.
public actor CityChainAutosaveStore {
  public typealias URLProvider = @Sendable () -> URL?

  private let cloudDocumentsURL: URLProvider
  private let localFileURL: URLProvider
  private let fileAccess: any CityChainAutosaveFileAccess
  private var deferCloudWritesUntilNextLoad = false

  public init(
    cloudDocumentsURL: @escaping URLProvider = {
      FileManager.default.url(
        forUbiquityContainerIdentifier: "iCloud.com.soundblaster.citychain")?
        .appendingPathComponent("Documents", isDirectory: true)
    },
    localFileURL: @escaping URLProvider = {
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("CityChain", isDirectory: true)
        .appendingPathComponent("autosave-v1.json", isDirectory: false)
    },
    fileAccess: (any CityChainAutosaveFileAccess)? = nil
  ) {
    self.cloudDocumentsURL = cloudDocumentsURL
    self.localFileURL = localFileURL
    self.fileAccess = fileAccess ?? CoordinatedAutosaveFileAccess()
  }

  /// Returns decoded saves in priority order so callers can validate routes and fall back.
  public func loadCandidates() -> [CityChainAutosaveCandidate] {
    deferCloudWritesUntilNextLoad = false
    var saves: [CityChainAutosaveCandidate] = []
    if let url = cloudSaveURL() {
      switch fileAccess.cloudReadiness(at: url) {
      case .missing:
        break
      case .downloadPending, .unavailable:
        deferCloudWritesUntilNextLoad = true
      case .ready:
        do {
          if let save = decodeSave(from: try fileAccess.read(from: url, coordinate: true)) {
            saves.append(CityChainAutosaveCandidate(save: save, location: .iCloudDocuments))
          }
        } catch {
          // A failed cloud read may be a transient download or ubiquity error.
          deferCloudWritesUntilNextLoad = true
        }
      }
    }
    if let url = localFileURL(), let save = readSave(at: url, coordinate: false) {
      saves.append(CityChainAutosaveCandidate(
        save: save, location: .applicationSupport,
        canPromoteToCloud: !deferCloudWritesUntilNextLoad))
    }
    return saves.sorted { lhs, rhs in
      if lhs.save.savedAt != rhs.save.savedAt {
        return lhs.save.savedAt > rhs.save.savedAt
      }
      return lhs.location == .iCloudDocuments && rhs.location == .applicationSupport
    }
  }

  /// Writes to iCloud first, then Application Support. Throws if neither write succeeds.
  @discardableResult
  public func write(_ save: CityChainAutosave) throws -> CityChainAutosaveLocation {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(save)

    var cloudFailure = "iCloud container is unavailable."
    if let url = writableCloudSaveURL() {
      do {
        try fileAccess.createDirectory(at: url.deletingLastPathComponent())
        try fileAccess.write(data, to: url, coordinate: true)
        return .iCloudDocuments
      } catch {
        cloudFailure = error.localizedDescription
      }
    }

    var localFailure = "Application Support directory is unavailable."
    if let url = localFileURL() {
      do {
        try fileAccess.createDirectory(at: url.deletingLastPathComponent())
        try fileAccess.write(data, to: url, coordinate: false)
        return .applicationSupport
      } catch {
        localFailure = error.localizedDescription
      }
    }
    throw CityChainAutosaveError.bothLocationsUnavailable(
      cloud: cloudFailure, local: localFailure)
  }

  private func cloudSaveURL() -> URL? {
    cloudDocumentsURL()?.appendingPathComponent("CityChain", isDirectory: true)
      .appendingPathComponent("autosave-v1.json", isDirectory: false)
  }

  private func writableCloudSaveURL() -> URL? {
    guard let url = cloudSaveURL() else { return nil }
    if deferCloudWritesUntilNextLoad {
      switch fileAccess.cloudReadiness(at: url) {
      case .ready, .missing:
        deferCloudWritesUntilNextLoad = false
      case .downloadPending, .unavailable:
        return nil
      }
    }
    return url
  }

  private func readSave(at url: URL, coordinate: Bool) -> CityChainAutosave? {
    guard let data = try? fileAccess.read(from: url, coordinate: coordinate) else { return nil }
    return decodeSave(from: data)
  }

  private func decodeSave(from data: Data) -> CityChainAutosave? {
    guard let save = try? JSONDecoder().decode(CityChainAutosave.self, from: data),
          save.version == CityChainAutosave.currentVersion,
          save.game.phase != .thinking
    else { return nil }
    return save
  }
}

private struct CoordinatedAutosaveFileAccess: CityChainAutosaveFileAccess {
  func cloudReadiness(at url: URL) -> CityChainCloudReadiness {
    let resourceValues: URLResourceValues
    do {
      resourceValues = try url.resourceValues(forKeys: [
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
      ])
    } catch {
      return FileManager.default.fileExists(atPath: url.path) ? .unavailable : .missing
    }

    guard resourceValues.isUbiquitousItem == true else {
      return FileManager.default.fileExists(atPath: url.path) ? .ready : .missing
    }
    guard let status = resourceValues.ubiquitousItemDownloadingStatus else { return .unavailable }
    guard status == .notDownloaded else { return .ready }

    do {
      try FileManager.default.startDownloadingUbiquitousItem(at: url)
      return .downloadPending
    } catch {
      return .unavailable
    }
  }

  func createDirectory(at url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  func read(from url: URL, coordinate: Bool) throws -> Data {
    guard coordinate else { return try Data(contentsOf: url) }
    var coordinatedData: Data?
    var coordinatedReadError: Error?
    var coordinationError: NSError?
    NSFileCoordinator(filePresenter: nil).coordinate(
      readingItemAt: url, options: .withoutChanges, error: &coordinationError
    ) { coordinatedURL in
      do {
        coordinatedData = try Data(contentsOf: coordinatedURL)
      } catch {
        coordinatedReadError = error
      }
    }
    if let coordinationError { throw coordinationError }
    if let coordinatedReadError { throw coordinatedReadError }
    guard let coordinatedData else { throw CocoaError(.fileReadUnknown) }
    return coordinatedData
  }

  func write(_ data: Data, to url: URL, coordinate: Bool) throws {
    guard coordinate else { return try data.write(to: url, options: .atomic) }
    var coordinatedWriteError: Error?
    var coordinationError: NSError?
    NSFileCoordinator(filePresenter: nil).coordinate(
      writingItemAt: url, options: .forReplacing, error: &coordinationError
    ) { coordinatedURL in
      do {
        try data.write(to: coordinatedURL, options: .atomic)
      } catch {
        coordinatedWriteError = error
      }
    }
    if let coordinationError { throw coordinationError }
    if let coordinatedWriteError { throw coordinatedWriteError }
  }
}
