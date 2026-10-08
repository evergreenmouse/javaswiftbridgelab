import SwiftUI
import UIKit

/// UIKit owns the drag gesture, lifted preview and drop/cancel animation.
/// The SwiftUI grid remains responsible for its application-specific slot sequence.
struct SystemCardDrag<Content: View>: UIViewControllerRepresentable {
  let cardID: UUID
  /// Restrict drops to another card of this same screen instance.
  let editorID: UUID
  let isEnabled: Bool
  let onLongPress: () -> Void
  let onBegin: (CGPoint) -> Bool
  let onMove: (CGPoint) -> Bool
  let onAcceptDrop: (CGPoint) -> Bool
  /// Freeze pointer previews before the system starts its landing animation.
  let onWillEnd: (Bool) -> Void
  /// Called once after session and animation completion; safe to reveal the card here.
  let onEnd: (Bool) -> Void
  /// Global destination frame for a committed drop or a cancelled return.
  let previewFrame: (Bool) -> CGRect?
  @ViewBuilder let content: () -> Content

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  /// A stationary hold enters edit mode; UIKit still owns lifting, dragging and landing.
  func makeUIViewController(context: Context) -> HostingContainer {
    let controller = HostingContainer(content: content())
    let drag = UIDragInteraction(delegate: context.coordinator)
    drag.isEnabled = true
    controller.view.addInteraction(drag)
    controller.view.addInteraction(UIDropInteraction(delegate: context.coordinator))
    let hold = UILongPressGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.didHold(_:)))
    hold.minimumPressDuration = 0.5
    hold.cancelsTouchesInView = true
    hold.delegate = context.coordinator
    controller.view.addGestureRecognizer(hold)
    return controller
  }

  func updateUIViewController(_ controller: HostingContainer, context: Context) {
    context.coordinator.parent = self
    controller.hosting.rootView = content()
  }

  /// A removed host cannot leave an active drag session or retained callbacks behind.
  static func dismantleUIViewController(
    _ controller: HostingContainer, coordinator: Coordinator
  ) {
    if let session = coordinator.activeSession {
      coordinator.parent.onWillEnd(false)
      coordinator.parent.onEnd(false)
      session.isActive = false
      session.onEnd = nil
      coordinator.activeSession = nil
    }
  }

  /// UIKit can reparent drag views in this plain root without modifying SwiftUI's root hierarchy.
  final class HostingContainer: UIViewController {
    let hosting: UIHostingController<Content>

    init(content: Content) {
      hosting = UIHostingController(rootView: content)
      super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(content:).") }

    override func viewDidLoad() {
      super.viewDidLoad()
      view.backgroundColor = .clear
      hosting.view.backgroundColor = .clear
      hosting.safeAreaRegions = []
      addChild(hosting)
      hosting.view.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(hosting.view)
      NSLayoutConstraint.activate([
        hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
        hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      ])
      hosting.didMove(toParent: self)
    }
  }

  @MainActor
  final class Coordinator: NSObject, UIDragInteractionDelegate, UIDropInteractionDelegate,
    UIGestureRecognizerDelegate
  {
    var parent: SystemCardDrag
    fileprivate var activeSession: CardDragSession?

    init(parent: SystemCardDrag) { self.parent = parent }

    @objc func didHold(_ recognizer: UILongPressGestureRecognizer) {
      guard recognizer.state == .began, parent.isEnabled else { return }
      parent.onLongPress()
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { true }

    func dragInteraction(
      _ interaction: UIDragInteraction, itemsForBeginning session: any UIDragSession
    ) -> [UIDragItem] {
      guard parent.isEnabled else { return [] }
      let local = CardDragSession(cardID: parent.cardID, editorID: parent.editorID)
      let item = UIDragItem(
        itemProvider: NSItemProvider(object: parent.cardID.uuidString as NSString))
      item.localObject = local
      session.localContext = local
      return [item]
    }

    func dragInteraction(
      _ interaction: UIDragInteraction, sessionWillBegin session: any UIDragSession
    ) {
      guard let window = interaction.view?.window,
        let local = session.localContext as? CardDragSession,
        parent.onBegin(session.location(in: window))
      else { return }
      local.isActive = true
      activeSession = local
      local.onEnd = { [weak self, weak local] committed in
        guard let self, let local, self.activeSession === local else { return }
        self.activeSession = nil
        self.parent.onEnd(committed)
      }
    }

    func dragInteraction(
      _ interaction: UIDragInteraction, sessionDidMove session: any UIDragSession
    ) {
      guard activeSession?.isActive == true, let window = interaction.view?.window else { return }
      _ = parent.onMove(session.location(in: window))
    }

    func dragInteraction(
      _ interaction: UIDragInteraction, session: any UIDragSession,
      willEndWith operation: UIDropOperation
    ) {
      guard let local = activeSession else { return }
      local.isActive = false
      parent.onWillEnd(local.accepted && operation == .move)
    }

    func dragInteraction(
      _ interaction: UIDragInteraction, session: any UIDragSession,
      didEndWith operation: UIDropOperation
    ) {
      guard let local = activeSession else { return }
      local.end(committed: local.accepted && operation == .move)
    }

    func dragInteraction(
      _ interaction: UIDragInteraction, sessionAllowsMoveOperation session: any UIDragSession
    ) -> Bool { true }
    func dragInteraction(
      _ interaction: UIDragInteraction,
      sessionIsRestrictedToDraggingApplication session: any UIDragSession
    ) -> Bool { true }

    func dragInteraction(
      _ interaction: UIDragInteraction, previewForLifting item: UIDragItem,
      session: any UIDragSession
    ) -> UITargetedDragPreview? {
      guard let view = interaction.view else { return nil }
      let parameters = UIDragPreviewParameters()
      parameters.backgroundColor = .clear
      parameters.visiblePath = UIBezierPath(
        roundedRect: view.bounds, cornerRadius: CardMetrics.cornerRadius)
      return UITargetedDragPreview(view: view, parameters: parameters)
    }

    func dragInteraction(
      _ interaction: UIDragInteraction, previewForCancelling item: UIDragItem,
      withDefault preview: UITargetedDragPreview
    ) -> UITargetedDragPreview? {
      retarget(preview, interactionView: interaction.view, committed: false)
    }

    func dragInteraction(
      _ interaction: UIDragInteraction, item: UIDragItem,
      willAnimateCancelWith animator: any UIDragAnimating
    ) {
      (item.localObject as? CardDragSession)?.waitForAnimation(animator)
    }

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession)
      -> Bool
    {
      localSession(session) != nil
    }

    func dropInteraction(
      _ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession
    ) -> UIDropProposal {
      guard localSession(session) != nil, let window = interaction.view?.window else {
        return UIDropProposal(operation: .forbidden)
      }
      return UIDropProposal(
        operation: parent.onMove(session.location(in: window)) ? .move : .forbidden)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession) {
      guard let local = localSession(session), let window = interaction.view?.window else { return }
      local.accepted = parent.onAcceptDrop(session.location(in: window))
    }

    func dropInteraction(
      _ interaction: UIDropInteraction, previewForDropping item: UIDragItem,
      withDefault preview: UITargetedDragPreview
    ) -> UITargetedDragPreview? {
      retarget(preview, interactionView: interaction.view, committed: true)
    }

    func dropInteraction(
      _ interaction: UIDropInteraction, item: UIDragItem,
      willAnimateDropWith animator: any UIDragAnimating
    ) {
      guard let local = item.localObject as? CardDragSession, local.editorID == parent.editorID
      else {
        return
      }
      // The target can be another card's coordinator, so completion belongs to the shared session.
      local.waitForAnimation(animator)
    }

    /// Reject external data, multiple items and already-ended sessions.
    private func localSession(_ session: any UIDropSession) -> CardDragSession? {
      guard session.items.count == 1,
        let local = session.localDragSession?.localContext as? CardDragSession,
        local.editorID == parent.editorID, local.isActive
      else { return nil }
      return local
    }

    /// Preserve the system preview while changing its animation destination.
    private func retarget(
      _ preview: UITargetedDragPreview, interactionView: UIView?, committed: Bool
    ) -> UITargetedDragPreview {
      guard let window = interactionView?.window, let frame = parent.previewFrame(committed) else {
        return preview
      }
      return preview.retargetedPreview(
        with: UIDragPreviewTarget(container: window, center: CGPoint(x: frame.midX, y: frame.midY)))
    }
  }
}

@MainActor
private final class CardDragSession {
  let cardID: UUID
  /// Restrict drops to another card of this same screen instance.
  let editorID: UUID
  var isActive = false
  var accepted = false
  var onEnd: ((Bool) -> Void)?
  private var committed: Bool?
  /// Drop and cancel animators may finish independently of the drag session delegate.
  private var pendingAnimations = 0

  init(cardID: UUID, editorID: UUID) {
    self.cardID = cardID
    self.editorID = editorID
  }

  /// Keep completion pending until every registered system animator has landed.
  func waitForAnimation(_ animator: any UIDragAnimating) {
    pendingAnimations += 1
    animator.addCompletion { [weak self] _ in
      guard let self else { return }
      self.pendingAnimations -= 1
      self.finishIfReady()
    }
  }

  func end(committed: Bool) {
    self.committed = committed
    finishIfReady()
  }

  /// Consume onEnd before invocation to guarantee one completion per session.
  private func finishIfReady() {
    guard let committed, pendingAnimations == 0 else { return }
    let completion = onEnd
    onEnd = nil
    completion?(committed)
  }
}
