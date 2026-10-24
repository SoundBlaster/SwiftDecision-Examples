import Foundation

/// Inference is explicitly selected; a stored key alone does not override this choice.
public enum OracleInferenceProvider: String, CaseIterable, Identifiable, Sendable {
  case jev
  case appleIntelligence
  case none

  public var id: Self { self }
}

/// Device-local preferences, separate from credentials in Keychain.
public struct OracleInferencePreferences {
  private let defaults: UserDefaults
  private let providerKey = "com.soundblaster.oracleball.inference-provider"
  private let normalizationKey = "com.soundblaster.oracleball.normalize-apple-output"

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// Migrates existing installations once, preserving their previous Jev/offline behavior.
  public func provider(hasJevKey: Bool) -> OracleInferenceProvider {
    if let rawValue = defaults.string(forKey: providerKey),
       let provider = OracleInferenceProvider(rawValue: rawValue) {
      return provider
    }
    let provider: OracleInferenceProvider = hasJevKey ? .jev : .none
    select(provider)
    return provider
  }

  public func select(_ provider: OracleInferenceProvider) {
    defaults.set(provider.rawValue, forKey: providerKey)
  }

  /// The pilot opts in to normalization. Strict output remains available for comparison.
  public var normalizesAppleOutput: Bool {
    get { defaults.object(forKey: normalizationKey) as? Bool ?? true }
    nonmutating set { defaults.set(newValue, forKey: normalizationKey) }
  }
}
