import LegacySampleMock
import UIKit

@MainActor
enum AppAssembly {
  static func makeRootViewController(configuration: AppConfiguration) -> StartViewController {
    let model = CompositeSampleModel(
      loadDelay: configuration.loadDelay, itemDelay: configuration.itemDelay,
      metricInterval: configuration.metricInterval)
    let advanced = SampleBoardScene(model: model)
    let coordinator = StartSceneCoordinator(sampleScene: advanced)
    return StartViewController(coordinator: coordinator)
  }
}
