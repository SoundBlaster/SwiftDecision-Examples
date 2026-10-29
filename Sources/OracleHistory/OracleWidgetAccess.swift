import Foundation

/// Shares the app's completed welcome state with its widget extension.
public enum OracleWidgetAccess {
  public static let suiteName = "group.ru.egormerkushev.oracle"
  public static let welcomeCompletedKey = "oracle.welcome.completed.v1"

  public static func isAllowed(in defaults: UserDefaults?) -> Bool {
    defaults?.bool(forKey: welcomeCompletedKey) == true
  }

  public static func synchronize(from appDefaults: UserDefaults, to sharedDefaults: UserDefaults?) {
    sharedDefaults?.set(appDefaults.bool(forKey: welcomeCompletedKey), forKey: welcomeCompletedKey)
  }
}
