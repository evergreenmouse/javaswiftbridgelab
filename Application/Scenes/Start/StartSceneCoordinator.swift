import UIKit

/// Ordinary coordinator: Start knows only this synchronous navigation contract.
final class StartSceneCoordinator: StartViewCoordination {
  private let sampleScene: any SampleBoardSceneBuilding

  init(sampleScene: any SampleBoardSceneBuilding) {
    self.sampleScene = sampleScene
  }

  var sampleSummary: String { sampleScene.sampleSummary }

  func makeSampleViewController() -> UIViewController {
    sampleScene.makeViewController()
  }
}
