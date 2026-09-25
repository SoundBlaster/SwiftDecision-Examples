import Foundation

enum OracleWidgetSharedState {
  static let suiteName = "group.com.soundblaster.oracleball"
  static let answerKey = "instant-prediction.answer"
  static let updatedAtKey = "instant-prediction.updated-at"

  static var defaults: UserDefaults? {
    UserDefaults(suiteName: suiteName)
  }
}
