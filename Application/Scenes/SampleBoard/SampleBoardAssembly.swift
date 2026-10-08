import LegacySampleMock
import UIKit

/// App-facing factory: callers provide the existing model and receive a ready UIKit controller.
@MainActor
protocol SampleBoardBuilding {
  func makeViewController(
    model: CompositeSampleModel, delegate: any SampleBoardViewControllerDelegate
  ) -> SampleBoardViewController
}

/// Constructs a fresh one-shot agent and ViewModel for each editor presentation.
@MainActor
struct SampleBoardAssembly: SampleBoardBuilding {
  func makeViewController(
    model: CompositeSampleModel, delegate: any SampleBoardViewControllerDelegate
  ) -> SampleBoardViewController {
    let viewModel = SampleBoardViewModel(agent: SampleAgent(model: model))
    return SampleBoardViewController(viewModel: viewModel, delegate: delegate)
  }
}
