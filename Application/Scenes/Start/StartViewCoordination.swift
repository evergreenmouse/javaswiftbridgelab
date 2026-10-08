import UIKit

/// Synchronous navigation interface used by the legacy UIKit screen.
protocol StartViewCoordination: AnyObject {
  var sampleSummary: String { get }
  func makeSampleViewController() -> UIViewController
}
