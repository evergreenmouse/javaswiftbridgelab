import SwiftUI
import UIKit

/// Hosts the editor directly; its root view retains the injected ViewModel for the controller's lifetime.
@MainActor
final class SampleBoardViewController: UIViewController {
  /// Weak ownership lets the presenter retain the editor without a delegate cycle.
  weak var delegate: (any SampleBoardViewControllerDelegate)?
  /// Only the UIKit child type is erased; the SwiftUI view keeps its concrete model and action types.
  /// Assigned after super.init so callbacks can safely capture this controller weakly.
  private var hostingController: UIViewController?

  init<Model: SampleBoardState & SampleBoardActions>(
    viewModel: Model,
    delegate: (any SampleBoardViewControllerDelegate)? = nil
  ) {
    super.init(nibName: nil, bundle: nil)
    self.delegate = delegate
    hostingController = UIHostingController(
      rootView: SampleBoardView(
        actions: viewModel, state: viewModel,
        onClose: { [weak self] in self?.requestClose() },
        onSave: { [weak self] in self?.requestSave() }))
    // Keep every modal exit on the delegate path instead of silently bypassing it with a swipe.
    isModalInPresentation = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(viewModel:delegate:).") }

  /// Emit an intention; the controller does not decide whether/how the host should dismiss it.
  func requestClose() { delegate?.sampleBoardDidRequestClose(self) }

  func requestSave() { delegate?.sampleBoardDidRequestSave(self) }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    guard let hostingController else { preconditionFailure("Missing editor hosting controller.") }

    // Containment forwards UIKit appearance, rotation and safe-area changes to SwiftUI.
    addChild(hostingController)
    let hostedView = hostingController.view!
    hostedView.backgroundColor = .clear
    hostedView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(hostedView)
    NSLayoutConstraint.activate([
      // Pin to the full container bounds: SwiftUI handles the inherited safe area.
      hostedView.topAnchor.constraint(equalTo: view.topAnchor),
      hostedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      hostedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      hostedView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    hostingController.didMove(toParent: self)
  }
}
