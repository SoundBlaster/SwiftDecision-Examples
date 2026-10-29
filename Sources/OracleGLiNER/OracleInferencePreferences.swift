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

  /// Legacy preference retained for older development installations; no longer gates GLiNER.
  public var isPilotEnabled: Bool {
    get { defaults.bool(forKey: pilotKey) }
    nonmutating set { defaults.set(newValue, forKey: pilotKey) }
  }

  /// GLiNER-only normalized entropy confidence threshold; existing policy defaults to 5%.
  public var glinerMinimumConfidence: Double {
    get {
      guard let value = defaults.object(forKey: "com.soundblaster.oracleball.gliner-confidence") as? Double,
            value.isFinite, (0 ... 1).contains(value) else { return 0.05 }
      return value
    }
    nonmutating set {
      guard newValue.isFinite, (0 ... 1).contains(newValue) else { return }
      defaults.set(newValue, forKey: "com.soundblaster.oracleball.gliner-confidence")
    }
  }

  /// Migrates existing Jev/offline installations; archived or disabled providers stay offline.
  public func provider(hasJevKey: Bool, supportsGLiNER: Bool, supportsJev: Bool = true) -> OracleInferenceProvider {
    let selection: OracleInferenceProvider
    if let raw = defaults.string(forKey: providerKey) {
      selection = OracleInferenceProvider(rawValue: raw) ?? .none
    } else {
      selection = hasJevKey ? .jev : .none
    }
    let unavailable = (selection == .gliner && !supportsGLiNER) || (selection == .jev && !supportsJev)
    let resolved: OracleInferenceProvider = unavailable ? .none : selection
    select(resolved)
    return resolved
  }

  public func select(_ provider: OracleInferenceProvider) {
    defaults.set(provider.rawValue, forKey: providerKey)
  }
}
