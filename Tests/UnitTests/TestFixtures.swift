import Foundation

@testable import JavaSwiftBridgeLab

/// Demo defaults belong to tests/mock construction, not production card entities.
extension SampleItemSnapshot {
  static var sample: SampleItemSnapshot { make() }
  static func make(
    id: UUID = UUID(), sampleName: String = "ArrayMap", runtime: SampleRuntime = .java,
    iterations: String = "1,234,567", metricValue: String = "42.00", variant: String = "BRIDGE V1",
    isLoading: Bool = false, hasError: Bool = false
  ) -> SampleItemSnapshot {
    SampleItemSnapshot(
      id: id, sampleName: sampleName, metricValue: metricValue, runtime: runtime,
      iterations: iterations, variant: variant, isLoading: isLoading, hasError: hasError)
  }
  func withMetric(_ value: String) -> SampleItemSnapshot {
    SampleItemSnapshot(
      id: id, sampleName: sampleName, metricValue: value, runtime: runtime,
      iterations: iterations, variant: variant, isLoading: isLoading, hasError: hasError)
  }

}

extension Result {
  var value: Success? { try? get() }
  var succeeded: Bool { if case .success = self { true } else { false } }
}

/// A Swift-only agent exercises the public contracts without importing the legacy mock.
@MainActor
final class TestSampleAgent: SampleAgentContract {
  enum Command: Equatable {
    case append
    case delete(UUID)
    case update(UUID, SampleItemChanges)
    case reorder([UUID])
    case layout(SampleLayout)
  }
  var snapshot: SampleSnapshot
  private var continuation: AsyncStream<SampleSnapshot>.Continuation?
  private var isFinished = false
  var commands: [Command] = []
  var starts = 0
  var acceptsCommands = true
  var holdsReorder = false
  var pendingReorder: CheckedContinuation<Bool, Never>?
  let appendedID = UUID()

  init(cards: [SampleItemSnapshot] = [.sample], kind: SampleLayout = .sequence) {
    snapshot = Self.state(cards, kind: kind)
  }

  static func state(
    _ cards: [SampleItemSnapshot], isActive: Bool = true, kind: SampleLayout = .sequence
  ) -> SampleSnapshot {
    SampleSnapshot(
      isUpToDate: true, isActive: isActive, validationError: "",
      kind: kind, items: cards
    )
  }

  func updates() -> AsyncStream<SampleSnapshot> {
    let (stream, continuation) = AsyncStream<SampleSnapshot>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    guard !isFinished, self.continuation == nil else {
      continuation.finish()
      return stream
    }
    continuation.onTermination = { [weak self] _ in
      Task { @MainActor in self?.finish() }
    }
    self.continuation = continuation
    starts += 1
    continuation.yield(snapshot)
    return stream
  }

  func send(_ value: SampleSnapshot) {
    snapshot = value
    continuation?.yield(value)
  }

  func finish() {
    isFinished = true
    continuation?.onTermination = nil
    continuation?.finish()
    continuation = nil
  }

  func appendCopy() -> Result<UUID, SampleFailure> {
    commands.append(.append)
    return acceptsCommands ? .success(appendedID) : .failure(.rejected)
  }
  func delete(id: UUID) -> Result<Void, SampleFailure> {
    commands.append(.delete(id))
    return acceptsCommands ? .success(()) : .failure(.rejected)
  }
  func update(id: UUID, changes: SampleItemChanges) -> Result<Void, SampleFailure> {
    commands.append(.update(id, changes))
    return acceptsCommands ? .success(()) : .failure(.rejected)
  }
  func reorder(ids: [UUID], expectedArrangement: [UUID]) async -> Result<Void, SampleFailure> {
    commands.append(.reorder(ids))
    if holdsReorder {
      let accepted = await withCheckedContinuation { pendingReorder = $0 }
      return accepted ? .success(()) : .failure(.rejected)
    }
    return acceptsCommands ? .success(()) : .failure(.rejected)
  }
  func selectKind(_ kind: SampleLayout) -> Result<Void, SampleFailure> {
    commands.append(.layout(kind))
    return acceptsCommands ? .success(()) : .failure(.rejected)
  }

}

/// Allow a structured observation task to consume the next buffered snapshot.
@MainActor
func eventually(_ condition: () -> Bool) async throws {
  struct Timeout: Error {}
  let deadline = ContinuousClock.now + .seconds(2)
  while !condition() {
    guard ContinuousClock.now < deadline else { throw Timeout() }
    try await Task.sleep(for: .milliseconds(5))
  }
}
