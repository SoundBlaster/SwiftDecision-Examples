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
        .background {
          DuoHingeProbe()
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
    }
  }
}

@MainActor
private final class CityChainApplicationDelegate: NSObject, UIApplicationDelegate, UIWindowSceneDelegate {
  private static var duoSceneIdentifiers = Set<String>()

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
    Self.orientationMask(for: windowScene, supportsDuoRotation: Self.duoSceneIdentifiers.contains(windowScene.session.persistentIdentifier))
  }

  func sceneDidDisconnect(_ scene: UIScene) {
    Self.duoSceneIdentifiers.remove(scene.session.persistentIdentifier)
  }

  @available(iOS, deprecated: 27.0, message: "Use UIWindowSceneDelegate.supportedInterfaceOrientations(for:) on iOS 27 and later")
  func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    guard let windowScene = window?.windowScene else { return .all }
    return Self.orientationMask(
      for: windowScene,
      supportsDuoRotation: Self.duoSceneIdentifiers.contains(windowScene.session.persistentIdentifier)
    )
  }

  static func recordHingeSupport(for window: UIWindow?) {
    guard let scene = window?.windowScene else { return }
    let identifier = scene.session.persistentIdentifier
    guard duoSceneIdentifiers.insert(identifier).inserted else { return }
    scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
  }

  private static func orientationMask(for scene: UIWindowScene, supportsDuoRotation: Bool) -> UIInterfaceOrientationMask {
    if scene.traitCollection.userInterfaceIdiom == .pad || supportsDuoRotation {
      return .all
    }
    return .portrait
  }

}

private struct DuoHingeProbe: UIViewRepresentable {
  func makeUIView(context: Context) -> HingeObservationView {
    HingeObservationView()
  }

  func updateUIView(_ view: HingeObservationView, context: Context) {}
}

@MainActor
private final class HingeObservationView: UIView {
  #if compiler(>=6.4)
  private var hingeInteraction: (any UIInteraction)?
  #endif

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updateHingeObservation()
  }

  private func updateHingeObservation() {
    #if compiler(>=6.4)
    if #available(iOS 27.1, *) {
      guard window != nil else {
        if let hingeInteraction {
          removeInteraction(hingeInteraction)
          self.hingeInteraction = nil
        }
        return
      }

      guard hingeInteraction == nil else { return }
      let interaction = UIHingeInteraction { [weak self] _, update in
        guard let self else { return }
        guard update.hinge != nil else { return }
        CityChainApplicationDelegate.recordHingeSupport(for: self.window)
      }
      hingeInteraction = interaction
      addInteraction(interaction)
      return
    }
    #endif

  }
}
