import UIKit

/// Demo configuration belongs to the app boundary, never to the editor or its legacy adapter.
struct AppConfiguration {
  private(set) var loadDelay: TimeInterval = 1.5
  let itemDelay: TimeInterval = 1.5
  private(set) var metricInterval: TimeInterval = 3
  private(set) var appearance: UIUserInterfaceStyle = .unspecified

  init(arguments: [String] = ProcessInfo.processInfo.arguments) {
    #if DEBUG
      if arguments.contains("--slow-mock-initial-load") { loadDelay = 4 }
      if arguments.contains("--disable-mock-metric-timer") { metricInterval = 0 }
      if arguments.contains("--dark-appearance") { appearance = .dark }
      if arguments.contains("--light-appearance") { appearance = .light }
    #endif
  }
}
