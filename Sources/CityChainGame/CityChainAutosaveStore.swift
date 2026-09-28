import Foundation

/// One versioned save envelope for CityChainApp's current game.
public struct CityChainAutosave: Codable, Sendable {
  public static let currentVersion = 1

  public let version: Int
  public let game: CityGameFixture

  public init(game: CityGameFixture) {
    version = Self.currentVersion
    self.game = game
  }
}

/// Stores the one automatic game save in the app's own Application Support directory.
public struct CityChainAutosaveStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL? = nil) {
    self.fileURL = fileURL ?? Self.defaultFileURL
  }

  public func load() -> CityChainAutosave? {
    guard let data = try? Data(contentsOf: fileURL),
          let save = try? JSONDecoder().decode(CityChainAutosave.self, from: data),
          save.version == CityChainAutosave.currentVersion,
          save.game.phase != .thinking
    else { return nil }
    return save
  }

  public func write(_ save: CityChainAutosave) {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      try encoder.encode(save).write(to: fileURL, options: .atomic)
    } catch {
      // Autosave is best-effort; a disk error must not interrupt a game turn.
    }
  }

  private static var defaultFileURL: URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first ?? FileManager.default.temporaryDirectory
    return support.appendingPathComponent("CityChain", isDirectory: true)
      .appendingPathComponent("autosave-v1.json", isDirectory: false)
  }
}
