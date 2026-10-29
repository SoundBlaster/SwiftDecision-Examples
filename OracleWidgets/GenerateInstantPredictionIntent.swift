import AppIntents
import Foundation
import OracleGame
import OracleHistory
import WidgetKit

struct GenerateInstantPredictionIntent: AppIntent {
  static let title: LocalizedStringResource = "Reveal a prediction"

  func perform() async throws -> some IntentResult {
    guard let defaults = OracleWidgetSharedState.defaults else {
      throw PredictionIntentError.sharedStorageUnavailable
    }
    guard OracleWidgetAccess.isAllowed(in: defaults) else {
      throw PredictionIntentError.welcomeRequired
    }
    let result = try await OracleGameEngine().randomAnswerWithTrace()
    let answer: OracleAnswer

    switch result.outcome {
    case let .accepted(value), let .fallback(value, _):
      answer = value
    case .abstained, .safetyIntervention:
      throw PredictionIntentError.noAnswer
    }

    defaults.set(answer.displayText, forKey: OracleWidgetSharedState.answerKey)
    defaults.set(Date.now, forKey: OracleWidgetSharedState.updatedAtKey)

    _ = await MainActor.run {
      OracleHistoryStore(defaults: defaults).append(
        question: "Instant prediction",
        answer: answer,
        pipeline: result.pipeline)
    }

    WidgetCenter.shared.reloadTimelines(ofKind: "com.soundblaster.oracleball.instant-prediction")
    return .result()
  }
}

private enum PredictionIntentError: Error, CustomLocalizedStringResourceConvertible {
  case noAnswer
  case sharedStorageUnavailable
  case welcomeRequired

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .noAnswer:
      "The oracle could not reveal a prediction."
    case .sharedStorageUnavailable:
      "Shared widget storage is unavailable."
    case .welcomeRequired:
      "Open Endless Answers and complete setup first."
    }
  }
}
