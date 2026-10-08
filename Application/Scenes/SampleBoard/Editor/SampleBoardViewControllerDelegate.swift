import Foundation

/// UIKit output contract; the scene owns closing and save confirmation.
@MainActor
protocol SampleBoardViewControllerDelegate: AnyObject, Sendable {
  func sampleBoardDidRequestClose(_ controller: SampleBoardViewController)
  func sampleBoardDidRequestSave(_ controller: SampleBoardViewController)
}
