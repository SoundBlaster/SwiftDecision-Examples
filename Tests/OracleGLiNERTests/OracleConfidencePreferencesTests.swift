import Foundation
import Testing
@testable import OracleGLiNER

@Test func confidencePreferenceKeepsDefaultAndRejectsInvalidValues() throws {
  let name = "oracle-confidence-" + UUID().uuidString
  let defaults = try #require(UserDefaults(suiteName: name))
  defer { defaults.removePersistentDomain(forName: name) }
  let preferences = OracleInferencePreferences(defaults: defaults)
  #expect(preferences.glinerMinimumConfidence == 0.05)
  preferences.glinerMinimumConfidence = 0
  #expect(OracleInferencePreferences(defaults: defaults).glinerMinimumConfidence == 0)
  preferences.glinerMinimumConfidence = 1
  #expect(preferences.glinerMinimumConfidence == 1)
  preferences.glinerMinimumConfidence = .nan
  preferences.glinerMinimumConfidence = -0.1
  preferences.glinerMinimumConfidence = 1.1
  #expect(preferences.glinerMinimumConfidence == 1)
}
