import Foundation
import OracleHistory
import Testing

@Test func widgetRequiresCompletedWelcomeAndFailsClosedWithoutStorage() throws {
  let appName = "oracle.widget-test.app.\(UUID().uuidString)"
  let sharedName = "oracle.widget-test.shared.\(UUID().uuidString)"
  let app = try #require(UserDefaults(suiteName: appName))
  let shared = try #require(UserDefaults(suiteName: sharedName))
  defer {
    app.removePersistentDomain(forName: appName)
    shared.removePersistentDomain(forName: sharedName)
  }

  #expect(!OracleWidgetAccess.isAllowed(in: nil))
  #expect(!OracleWidgetAccess.isAllowed(in: shared))
  app.set(true, forKey: OracleWidgetAccess.welcomeCompletedKey)
  OracleWidgetAccess.synchronize(from: app, to: shared)
  #expect(OracleWidgetAccess.isAllowed(in: shared))
  app.removeObject(forKey: OracleWidgetAccess.welcomeCompletedKey)
  OracleWidgetAccess.synchronize(from: app, to: shared)
  #expect(!OracleWidgetAccess.isAllowed(in: shared))
}
