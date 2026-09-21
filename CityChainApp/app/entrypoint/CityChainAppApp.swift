import SwiftUI

@main
struct CityChainAppApp: App {
  @State private var model: CityChainPageModel

  init() {
    _model = State(initialValue: AppDependencies().makePageModel())
  }

  var body: some Scene {
    WindowGroup {
      CityChainPage(model: model)
    }
  }
}
