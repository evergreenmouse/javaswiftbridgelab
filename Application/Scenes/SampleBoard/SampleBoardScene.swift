import LegacySampleMock
import UIKit

/// The synchronous entry point exposed to legacy UIKit coordinators.
/// Call only on the main thread, as required by UIKit and the legacy model.
protocol SampleBoardSceneBuilding: AnyObject {
  var sampleSummary: String { get }
  func makeViewController() -> UIViewController
}

/// Owns the legacy model across editor presentations.
/// Swift concurrency stays inside the SampleBoard scene and its agent.
@MainActor
final class SampleBoardScene: SampleBoardSceneBuilding,
  SampleBoardViewControllerDelegate
{
  private let model: CompositeSampleModel
  private let builder: any SampleBoardBuilding

  init(
    model: CompositeSampleModel,
    builder: any SampleBoardBuilding = SampleBoardAssembly()
  ) {
    self.model = model
    self.builder = builder
  }

  /// Check the legacy caller's executor synchronously; no task or dispatch is created.
  nonisolated func makeViewController() -> UIViewController {
    MainActor.assumeIsolated {
      let controller = builder.makeViewController(model: model, delegate: self)
      controller.modalPresentationStyle = .fullScreen
      return controller
    }
  }

  nonisolated var sampleSummary: String {
    MainActor.assumeIsolated {
      model.items.isEmpty
        ? "Add samples and explore the Java → Swift bridge."
        : "\(model.items.count) / \(SampleLimits.items) items"
    }
  }

  func sampleBoardDidRequestClose(_ controller: SampleBoardViewController) {
    controller.dismiss(animated: true)
  }

  func sampleBoardDidRequestSave(_ controller: SampleBoardViewController) {
    guard let presenter = controller.presentingViewController else { return }
    controller.dismiss(animated: true) { [weak presenter] in
      guard let presenter else { return }
      let alert = UIAlertController(
        title: "Sample saved", message: "Your sample has been saved.", preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "OK", style: .default))
      presenter.present(alert, animated: true)
    }
  }
}
