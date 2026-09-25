import SwiftUI
import WidgetKit

@main
struct OracleWidgetsBundle: WidgetBundle {
  var body: some Widget {
    InstantPredictionWidget()
    OracleAppPredictionWidget()
  }
}
