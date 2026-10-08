/// An editor-owned draft is separate from the live card that continues receiving metrics.
struct SampleItemDraft: Equatable {
  var sampleName: String
  var runtime: SampleRuntime
  var iterations: String
  var metricValue: String
  var variant: String

  init(card: SampleItemSnapshot) {
    sampleName = card.sampleName
    runtime = card.runtime
    iterations = card.iterations
    metricValue = card.metricValue
    variant = card.variant
  }

  /// Compare against the editor's original card, not a newer snapshot received while editing.
  func changes(from original: SampleItemSnapshot) -> SampleItemChanges {
    SampleItemChanges(
      sampleName: sampleName == original.sampleName ? nil : sampleName,
      metricValue: metricValue == original.metricValue ? nil : metricValue,
      runtime: runtime == original.runtime ? nil : runtime,
      iterations: iterations == original.iterations ? nil : iterations,
      variant: variant == original.variant ? nil : variant)
  }
}
