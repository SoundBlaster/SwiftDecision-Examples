import Foundation
import XCTest
import OracleGame

final class OracleInferencePreferencesTests: XCTestCase {
  func testMigrationPreservesExistingKeyBehaviorOnce() {
    withPreferences { preferences in
      XCTAssertEqual(preferences.provider(hasJevKey: true), .jev)
      XCTAssertEqual(preferences.provider(hasJevKey: false), .jev)
    }
    withPreferences { preferences in
      XCTAssertEqual(preferences.provider(hasJevKey: false), .none)
      XCTAssertEqual(preferences.provider(hasJevKey: true), .none)
    }
  }

  func testExplicitSelectionSurvivesKeyChangesAndReload() {
    withPreferences { preferences in
      for provider in OracleInferenceProvider.allCases {
        preferences.select(provider)
        XCTAssertEqual(preferences.provider(hasJevKey: true), provider)
        XCTAssertEqual(preferences.provider(hasJevKey: false), provider)
      }
    }
  }

  func testNormalizationIsOptedInButCanBeDisabledPersistently() {
    withPreferences { preferences in
      XCTAssertTrue(preferences.normalizesAppleOutput)
      preferences.normalizesAppleOutput = false
      XCTAssertFalse(preferences.normalizesAppleOutput)
    }
  }

  func testPreferencesSurviveStoreRecreation() {
    let suite = "OracleInferencePreferencesReload.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = OracleInferencePreferences(defaults: defaults)
    preferences.select(.appleIntelligence)
    preferences.normalizesAppleOutput = false
    let reloaded = OracleInferencePreferences(defaults: UserDefaults(suiteName: suite)!)
    XCTAssertEqual(reloaded.provider(hasJevKey: true), .appleIntelligence)
    XCTAssertFalse(reloaded.normalizesAppleOutput)
  }

  private func withPreferences(_ body: (OracleInferencePreferences) -> Void) {
    let suite = "OracleInferencePreferencesTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    body(OracleInferencePreferences(defaults: defaults))
  }
}
