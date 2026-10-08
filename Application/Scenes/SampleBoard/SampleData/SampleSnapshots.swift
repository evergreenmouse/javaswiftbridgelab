import Foundation

/// Immutable screen-relevant values copied from the legacy model on its owning actor.
struct SampleItemSnapshot: Identifiable, Equatable, Sendable {
  /// Stable source identity, preserved across updates and reordering.
  let id: UUID
  let sampleName: String
  /// Legacy-formatted metric, displayed without changing its stored value.
  let metricValue: String
  let runtime: SampleRuntime
  let iterations: String
  let variant: String
  /// True while this individual item is waiting for its initial source data.
  let isLoading: Bool
  /// True when the source reports a sample error and marks this item as affected.
  var hasError: Bool = false
}

/// One coherent sample state. A malformed source is represented by failure.
struct SampleSnapshot: Equatable, Sendable {
  /// Whether the whole sample collection has an authoritative current state.
  let isUpToDate: Bool
  /// Connection/activity flag; unavailable sources cannot accept commands.
  let isActive: Bool
  /// Data validation supplied by the source; editing stays available to correct it.
  let validationError: String
  let kind: SampleLayout?
  let items: [SampleItemSnapshot]
  /// Adapter/transport failure is distinct from data validation.
  var failure: SampleFailure? = nil

  /// Also protects consumers of alternative conforming agents, not just the ObjC adapter.
  var issue: SampleFailure? {
    if let failure { return failure }
    guard kind != nil else { return .invalidSnapshot }
    guard items.count <= SampleLimits.items,
      Set(items.map(\.id)).count == items.count
    else { return .invalidSnapshot }
    return nil
  }
}

/// Partial edits: nil means that the latest source value must remain untouched.
struct SampleItemChanges: Equatable, Sendable {
  var sampleName: String? = nil
  var metricValue: String? = nil
  var runtime: SampleRuntime? = nil
  var iterations: String? = nil
  var variant: String? = nil
}
