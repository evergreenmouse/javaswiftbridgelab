import UIKit

/// UIKit host using only synchronous coordination and presentation.
final class StartViewController: UIViewController {
  private let coordinator: any StartViewCoordination
  private let summaryLabel = UILabel()

  init(coordinator: any StartViewCoordination) {
    self.coordinator = coordinator
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(coordinator:).") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground

    let title = UILabel()
    title.text = "Java → Swift Lab"
    title.font = .preferredFont(forTextStyle: .largeTitle)
    title.adjustsFontForContentSizeCategory = true
    title.numberOfLines = 0
    title.textAlignment = .center
    title.accessibilityTraits = .header

    summaryLabel.font = .preferredFont(forTextStyle: .body)
    summaryLabel.adjustsFontForContentSizeCategory = true
    summaryLabel.textColor = .secondaryLabel
    summaryLabel.numberOfLines = 0
    summaryLabel.textAlignment = .center
    summaryLabel.accessibilityIdentifier = "start-sample-summary"
    updateSummary()

    var configuration = UIButton.Configuration.filled()
    configuration.title = "Open sample board"
    configuration.image = UIImage(systemName: "square.grid.3x3")
    configuration.imagePadding = 8
    configuration.cornerStyle = .large
    configuration.baseBackgroundColor = .label
    configuration.baseForegroundColor = .systemBackground
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 14, leading: 20, bottom: 14, trailing: 20)
    let button = UIButton(configuration: configuration)
    button.accessibilityIdentifier = "open-sample-board"
    button.addAction(UIAction { [weak self] _ in self?.openEditor() }, for: .touchUpInside)

    let stack = UIStackView(arrangedSubviews: [title, summaryLabel, button])
    stack.axis = .vertical
    stack.spacing = 20
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    let preferredWidth = stack.widthAnchor.constraint(
      equalTo: view.safeAreaLayoutGuide.widthAnchor, constant: -48)
    preferredWidth.priority = .defaultHigh
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
      stack.leadingAnchor.constraint(
        greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(
        lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
      stack.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
      preferredWidth,
    ])
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    updateSummary()
  }

  private func openEditor() {
    guard presentedViewController == nil else { return }
    present(coordinator.makeSampleViewController(), animated: true)
  }

  private func updateSummary() {
    summaryLabel.text = coordinator.sampleSummary
  }
}
