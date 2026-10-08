import Foundation
import Observation

/// Keep the lifted identity until UIKit's drop/cancel animation has completed.
enum DragPresentationState: Equatable {
  struct Session: Equatable {
    let id: UUID
    let cardID: UUID
    let originalIndex: Int
  }
  case idle
  case dragging(Session)
  case landing(Session)

  var session: Session? {
    switch self {
    case .idle: nil
    case .dragging(let session), .landing(let session): session
    }
  }

  var isLanding: Bool { if case .landing = self { true } else { false } }
}

/// Screen-owned preview IDs and visual state; UIKit owns the native drag session.
@MainActor @Observable
final class SampleBoardInteractionState {
  let editorID = UUID()
  var isEditing = false
  var reorder: SampleCardReorderPreview?
  var flippingID: UUID?
  private(set) var drag: DragPresentationState = .idle
  var isBusy: Bool { flippingID != nil || reorder != nil || drag.session != nil }

  func beginDrag(cardID: UUID, index: Int) {
    drag = .dragging(.init(id: UUID(), cardID: cardID, originalIndex: index))
    isEditing = true
  }

  func beginLanding() {
    if let session = drag.session { drag = .landing(session) }
  }

  /// An obsolete completion cannot finish a newer drag.
  func endDrag(sessionID: UUID) {
    if drag.session?.id == sessionID { drag = .idle }
  }
}
