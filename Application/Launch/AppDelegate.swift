import UIKit

/// UIKit owns application/scene lifecycle; feature state stays in the injected SwiftUI editor.
@main @MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(
      name: "SampleBoard", sessionRole: connectingSceneSession.role)
    configuration.sceneClass = UIWindowScene.self
    configuration.delegateClass = AppSceneDelegate.self
    return configuration
  }
}
