import Foundation

/// Sample runtime; an unknown legacy value must never silently become JAVA.
enum SampleRuntime: String, CaseIterable, Sendable {
  case java = "JAVA"
  case swift = "SWIFT"
}

/// Supported sample layouts, independent of grid geometry and display titles.
enum SampleLayout: String, CaseIterable, Sendable {
  case radial
  case sequence
  case stagedRadial = "staged-radial"
  case matrix = "matrix"
  case stagedMatrix = "staged-matrix"
}

/// Shared application limits; the SDK still authoritatively validates its commands.
enum SampleLimits {
  static let items = 8
}

/// Failures crossing the adapter boundary contain no Objective-C objects or UI strings.
enum SampleFailure: Error, Equatable, Sendable {
  case inactive, notUpToDate, itemMissing, itemLoading, capacityReached, lastItem
  case conflict, rejected, invalidSnapshot
  case unsupportedValue(String)
}
