import Foundation
import LegacySampleMock

/// One scene, one consumer, one registration. Raw SDK access stays on MainActor.
actor SampleAgent: NSObject, SampleAgentContract, CompositeSampleModelListener {
  @MainActor private let model: CompositeSampleModel
  @MainActor private var continuation: AsyncStream<SampleSnapshot>.Continuation?
  @MainActor private var lastSnapshot: SampleSnapshot?
  @MainActor private var isFinished = false

  @MainActor
  init(model: CompositeSampleModel) {
    self.model = model
    super.init()
  }

  func updates() async -> AsyncStream<SampleSnapshot> { await addListener() }
  func finish() async { await removeListener() }

  @MainActor
  private func addListener() -> AsyncStream<SampleSnapshot> {
    let (stream, continuation) = AsyncStream<SampleSnapshot>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    guard !isFinished, self.continuation == nil else {
      continuation.finish()
      return stream
    }
    self.continuation = continuation
    continuation.onTermination = { [weak self] _ in Task { await self?.finish() } }
    model.addListener(self)
    publish()
    return stream
  }

  /// The model retains this listener; cancellation or explicit finish breaks that ownership.
  @MainActor
  private func removeListener() {
    isFinished = true
    guard let continuation else { return }
    self.continuation = nil
    lastSnapshot = nil
    continuation.onTermination = nil
    continuation.finish()
    model.removeListener(self)
  }

  @MainActor
  private func publish() {
    guard let continuation else { return }
    let snapshot = Self.snapshot(of: model)
    guard snapshot != lastSnapshot else { return }
    lastSnapshot = snapshot
    continuation.yield(snapshot)
  }

  /// Readiness checks and mutation execute together on the model's owning executor.
  @MainActor
  private func command<Value: Sendable>(
    _ action: @MainActor @Sendable (CompositeSampleModel) -> Result<Value, SampleFailure>
  ) -> Result<Value, SampleFailure> {
    guard continuation != nil, model.isActive else { return .failure(.inactive) }
    guard model.isUpToDate else { return .failure(.notUpToDate) }
    return action(model)
  }

  func appendCopy() async -> Result<UUID, SampleFailure> {
    await command { model in
      guard model.items.count < SampleLimits.items else {
        return .failure(.capacityReached)
      }
      guard model.items.last?.isLoading == false else { return .failure(.itemLoading) }
      guard let item = model.appendCopy() else { return .failure(.rejected) }
      return .success(item.identifier)
    }
  }

  func delete(id: UUID) async -> Result<Void, SampleFailure> {
    await command { model in
      guard model.items.contains(where: { $0.identifier == id }) else {
        return .failure(.itemMissing)
      }
      guard model.items.count > 1 else { return .failure(.lastItem) }
      return model.deleteItem(id) ? .success(()) : .failure(.rejected)
    }
  }

  /// Raw SDK dictionary keys are confined to this adapter.
  func update(id: UUID, changes: SampleItemChanges) async -> Result<Void, SampleFailure> {
    await command { model in
      guard let item = model.items.first(where: { $0.identifier == id }) else {
        return .failure(.itemMissing)
      }
      guard !item.isLoading else { return .failure(.itemLoading) }
      let fields = [
        "sampleName": changes.sampleName, "metricValue": changes.metricValue, "runtime": changes.runtime?.rawValue,
        "iterations": changes.iterations, "variant": changes.variant,
      ].compactMapValues { $0 }
      return model.updateItem(id, changes: fields) ? .success(()) : .failure(.rejected)
    }
  }

  func reorder(ids: [UUID], expectedArrangement: [UUID]) async -> Result<Void, SampleFailure> {
    await command { model in
      guard model.items.map(\.identifier) == expectedArrangement else {
        return .failure(.conflict)
      }
      return model.reorderItems(ids) ? .success(()) : .failure(.rejected)
    }
  }

  func selectKind(_ kind: SampleLayout) async -> Result<Void, SampleFailure> {
    await command { model in
      model.selectLayoutTag(kind.rawValue)
      return model.layoutTag == kind.rawValue ? .success(()) : .failure(.rejected)
    }
  }

  /// Validate before projecting: invalid identities/values never reach dictionary or grid assumptions.
  @MainActor
  private static func snapshot(of model: CompositeSampleModel) -> SampleSnapshot {
    let kind = SampleLayout(rawValue: model.layoutTag)
    var failure: SampleFailure?
    if kind == nil { failure = .unsupportedValue(model.layoutTag) }
    let items = model.items
    if items.count > SampleLimits.items || Set(items.map(\.identifier)).count != items.count
    {
      failure = .invalidSnapshot
    }
    let hasError = model.error
    var values: [SampleItemSnapshot] = []
    for item in items {
      guard let runtime = SampleRuntime(rawValue: item.runtime) else {
        failure = .unsupportedValue(item.runtime)
        break
      }
      values.append(
        SampleItemSnapshot(
          id: item.identifier, sampleName: item.sampleName, metricValue: item.metricValue,
          runtime: runtime, iterations: item.iterations,
          variant: item.variant, isLoading: item.isLoading,
          hasError: hasError && item.error))
    }
    return SampleSnapshot(
      isUpToDate: model.isUpToDate, isActive: model.isActive,
      validationError: model.validationError,
      kind: kind, items: failure == nil ? values : [], failure: failure)
  }

  nonisolated func onCompositeSampleModelChange() { changed() }
  nonisolated func onCompositeSampleModelUpToDate() { changed() }
  nonisolated func onCompositeSampleModelInactive() { changed() }
  nonisolated func onCompositeSampleModelStateChange() { changed() }
  nonisolated func onCompositeSampleModelNotUpToDate() { changed() }
  nonisolated func onCompositeSampleModelLayoutTagChange() { changed() }

  private nonisolated func changed() { MainActor.assumeIsolated { publish() } }
}
