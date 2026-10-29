import Foundation
import OracleHistory

enum OracleWidgetSharedState {
  static let suiteName = OracleWidgetAccess.suiteName
  static let answerKey = "instant-prediction.answer"
  static let updatedAtKey = "instant-prediction.updated-at"

  static var defaults: UserDefaults? {
    UserDefaults(suiteName: suiteName)
  }
}
