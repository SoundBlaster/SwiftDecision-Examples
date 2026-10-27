import Foundation

public typealias OracleGLiNERDiagnosticSink = @Sendable (OracleGLiNERInstallationEvent) async -> Void

/// Fixed technical fields only; deliberately excludes user text, credentials and raw errors.
public enum OracleGLiNERInstallationEvent: Codable, Equatable, Sendable {
  case started(version: String, build: String)
  case stage(OracleGLiNERInstallationFailure.Stage)
  case progress(Int)
  case fileRequested(path: String)
  case fileRead(path: String, bytes: Int)
  case downloadAvailable
  case inventoryVerified
  case activated
  case cacheReleased
  case cacheReleaseFailed(OracleGLiNERInstallationFailure)
  case providerReady
  case completed
  case cancelled
  case failed(OracleGLiNERInstallationFailure)

  public var message: String {
    switch self {
    case let .started(version, build): "Install gliner-small-v1 · app \(version) (\(build))"
    case let .stage(stage): "Stage: \(stage.rawValue)"
    case let .progress(percent): "Download: \(percent)%"
    case let .fileRequested(path): "Reading: \(path)"
    case let .fileRead(path, bytes): "Read: \(path) · \(bytes) bytes"
    case .downloadAvailable: "Apple reports asset pack locally available"
    case .inventoryVerified: "Pinned inventory and SHA-256 verified"
    case .activated: "Model activated in app storage"
    case .cacheReleased: "Download cache released"
    case let .cacheReleaseFailed(failure): "Cache cleanup failed: \(Self.details(failure))"
    case .providerReady: "GLiNER provider ready after load and warm-up"
    case .completed: "Installation completed"
    case .cancelled: "Installation cancelled"
    case let .failed(failure): "FAILED: \(Self.details(failure))"
    }
  }

  public var isFailure: Bool {
    switch self {
    case .failed, .cacheReleaseFailed: true
    default: false
    }
  }

  private static func details(_ failure: OracleGLiNERInstallationFailure) -> String {
    "\(failure.stage.rawValue) · \(failure.domain) · code \(failure.code)"
  }
}

/// Bounded, serializable journal. Callers provide timestamps for deterministic tests.
public struct OracleGLiNERInstallationLog: Codable, Sendable {
  public struct Entry: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let event: OracleGLiNERInstallationEvent
  }
  public static let maximumEntries = 300
  public private(set) var entries: [Entry] = []

  public init() {}

  private enum CodingKeys: String, CodingKey { case entries }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    entries = Array(try container.decode([Entry].self, forKey: .entries).suffix(Self.maximumEntries))
  }

  public mutating func record(_ event: OracleGLiNERInstallationEvent, at date: Date = Date()) {
    if case let .progress(value) = event {
      guard (0 ... 100).contains(value) else { return }
      let rounded = value == 100 ? 100 : value / 5 * 5
      if let last = entries.last, last.event == .progress(rounded) { return }
      append(.progress(rounded), at: date)
    } else {
      append(event, at: date)
    }
  }

  private mutating func append(_ event: OracleGLiNERInstallationEvent, at date: Date) {
    entries.append(Entry(id: UUID(), date: date, event: event))
    if entries.count > Self.maximumEntries {
      entries.removeFirst(entries.count - Self.maximumEntries)
    }
  }

  public mutating func clear() { entries.removeAll() }

  public func text() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return (["Oracle model installation log"] + entries.map {
      "\(formatter.string(from: $0.date))  \($0.event.message)"
    }).joined(separator: "\n")
  }
}
