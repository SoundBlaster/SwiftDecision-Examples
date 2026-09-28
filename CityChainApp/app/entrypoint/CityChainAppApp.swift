import SwiftUI
import CityChainGame

@main
struct CityChainAppApp: App {
  @State private var model: CityChainPageModel

  init() {
#if DEBUG
    let (fixture, error) = AppDependencies.debugFixtureFromLaunchArguments(CommandLine.arguments)
    _model = State(initialValue: AppDependencies().makePageModel(debugFixture: fixture, fixtureError: error))
#else
    _model = State(initialValue: AppDependencies().makePageModel())
#endif
  }

  var body: some Scene {
    WindowGroup {
      CityChainPage(model: model)
    }
  }
}
