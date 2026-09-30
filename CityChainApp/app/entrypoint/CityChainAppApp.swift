import SwiftUI
import UIKit
import CityChainGame

@main
struct CityChainAppApp: App {
  @UIApplicationDelegateAdaptor(CityChainApplicationDelegate.self) private var applicationDelegate
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

@MainActor
private final class CityChainApplicationDelegate: NSObject, UIApplicationDelegate, UIWindowSceneDelegate {
  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    configuration.delegateClass = Self.self
    return configuration
  }

  @available(iOS 27.0, *)
  func supportedInterfaceOrientations(for windowScene: UIWindowScene) -> UIInterfaceOrientationMask {
    Self.orientationMask(for: windowScene)
  }

  @available(iOS, deprecated: 27.0, message: "Use UIWindowSceneDelegate.supportedInterfaceOrientations(for:) on iOS 27 and later")
  func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    guard let windowScene = window?.windowScene else { return .all }
    return Self.orientationMask(for: windowScene)
  }

  private static func orientationMask(for scene: UIWindowScene) -> UIInterfaceOrientationMask {
    let hasTwoPanelSize = scene.traitCollection.horizontalSizeClass == .regular
      && scene.traitCollection.verticalSizeClass == .regular
    if scene.traitCollection.userInterfaceIdiom == .pad || hasTwoPanelSize {
      return .all
    }
    return .portrait
  }
}
