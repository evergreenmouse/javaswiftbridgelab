import UIKit

/// Each window owns an independent UIKit Start scene and its injected sample model.
@MainActor
final class AppSceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: windowScene)
    let configuration = AppConfiguration()
    window.rootViewController = AppAssembly.makeRootViewController(configuration: configuration)
    window.overrideUserInterfaceStyle = configuration.appearance
    self.window = window
    window.makeKeyAndVisible()
  }
}
