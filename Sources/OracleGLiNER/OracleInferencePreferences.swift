import Foundation

/// Explicit inference selection, independent of stored credentials.
public enum OracleInferenceProvider: String, CaseIterable, Sendable, Identifiable {
  case jev
  case gliner
  case none

  public var id: Self { self }
  public var isJev: Bool { self == .jev }
}

/// Device-local opt-in preferences; model files and credentials are stored separately.
public struct OracleInferencePreferences {
  private let defaults: UserDefaults
  private let providerKey = "com.soundblaster.oracleball.inference-provider"
  private let pilotKey = "com.soundblaster.oracleball.gliner-pilot"

  public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  public var isPilotEnabled: Bool {
    get { defaults.bool(forKey: pilotKey) }
    nonmutating set { defaults.set(newValue, forKey: pilotKey) }
  }

  /// Migrates existing Jev/offline installations; archived or disabled providers stay offline.
  public func provider(hasJevKey: Bool, supportsGLiNER: Bool) -> OracleInferenceProvider {
    let selection: OracleInferenceProvider
    if let raw = defaults.string(forKey: providerKey) {
      selection = OracleInferenceProvider(rawValue: raw) ?? .none
    } else {
      selection = hasJevKey ? .jev : .none
    }
    let resolved = selection == .gliner && (!isPilotEnabled || !supportsGLiNER) ? .none : selection
    select(resolved)
    return resolved
  }

  public func select(_ provider: OracleInferenceProvider) {
    defaults.set(provider.rawValue, forKey: providerKey)
  }
}
