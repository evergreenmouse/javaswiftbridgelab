import Foundation
import LegacySampleMock
import Testing

@testable import JavaSwiftBridgeLab

@MainActor
private final class Recorder<Value: Sendable> {
  var values: [Value] = []
  var last: Value? { values.last }
  func collect(_ stream: AsyncStream<Value>) -> Task<Void, Never> {
    Task { @MainActor [weak self] in
      for await value in stream { self?.values.append(value) }
    }
  }
}

@MainActor
struct SampleAgentTests {
  private struct Timeout: Error {}

  private func eventually(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !condition() {
      guard ContinuousClock.now < deadline else {
        Issue.record("Timed out waiting for a source/stream state transition")
        throw Timeout()
      }
      try await Task.sleep(for: .milliseconds(5))
    }
  }

  private func source(load: TimeInterval = 0.02, item: TimeInterval = 0.06) -> CompositeSampleModel {
    CompositeSampleModel(loadDelay: load, itemDelay: item, metricInterval: 0)
  }

  @Test func initialAndPerItemLoadingProduceStableSnapshots() async throws {
    let source = source(load: 0.08)
    let agent = SampleAgent(model: source)
    let recorder = Recorder<SampleSnapshot>()
    let task = recorder.collect(await agent.updates())
    defer { task.cancel() }
    try await eventually { recorder.last != nil }
    #expect(recorder.last?.items.isEmpty == true)
    #expect(recorder.last?.isUpToDate == false)
    try await eventually { recorder.last?.isUpToDate == true }
    let first = try #require(recorder.last?.items.first)
    #expect(!first.isLoading)
    let id = try #require((await agent.appendCopy()).value)
    try await eventually { recorder.last?.items.last?.id == id }
    #expect(recorder.last?.items.last?.isLoading == true)
    #expect(source.listenerCount == 1)
    try await eventually { recorder.last?.items.last?.isLoading == false }
    #expect(recorder.last?.items.first == first)
    #expect(recorder.last?.items.last?.id == id)
  }

  @Test func parentCallbacksIncludeItemChangesAndMetrics() async throws {
    let source = source()
    let agent = SampleAgent(model: source)
    let recorder = Recorder<SampleSnapshot>()
    let task = recorder.collect(await agent.updates())
    defer { task.cancel() }
    try await eventually { recorder.last?.isUpToDate == true }
    let original = try #require(recorder.last?.items.first)
    let item = try #require(source.items.first)
    #expect(
      source.updateItem(
        item.identifier,
        changes: [
          "sampleName": "StringFold", "runtime": "SWIFT", "metricValue": "3000.00",
          "iterations": "20", "variant": "NATIVE V1",
        ]))
    try await eventually { recorder.last?.items.first?.sampleName == "StringFold" }
    let updated = try #require(recorder.last?.items.first)
    #expect(
      updated.runtime == .swift && updated.iterations == "20" && updated.variant == "NATIVE V1")
    source.simulateMetricTick()
    try await eventually { recorder.last?.items.first?.metricValue == "3000.25" }
    #expect(original.sampleName == "ArrayMap" && original.metricValue == "42.00")
    #expect(recorder.last?.items.first?.id == original.id)
  }

  @Test func complexStateValidationAndGroupEventsAreForwarded() async throws {
    let source = source()
    let agent = SampleAgent(model: source)
    let recorder = Recorder<SampleSnapshot>()
    let task = recorder.collect(await agent.updates())
    defer { task.cancel() }
    try await eventually { recorder.last?.isUpToDate == true }
    source.simulateUp(toDate: false)
    try await eventually { recorder.last?.isUpToDate == false }
    source.simulateUp(toDate: true)
    try await eventually { recorder.last?.isUpToDate == true }
    source.simulateActive(false)
    try await eventually { recorder.last?.isActive == false }
    #expect((await agent.appendCopy()).value == nil)
    source.simulateActive(true)
    #expect((await agent.selectKind(.sequence)).succeeded)
    try await eventually {
      recorder.last?.kind == .sequence
    }
    let id = try #require(source.items.first?.identifier)
    #expect(source.updateItem(id, changes: ["sampleName": ""]))
    try await eventually { recorder.last?.validationError.isEmpty == false }
    #expect(source.updateItem(id, changes: ["sampleName": "ArrayMap"]))
    try await eventually { recorder.last?.validationError.isEmpty == true }
  }

  @Test func sourceErrorFlagsFollowEntriesThroughReorderCorrectionAndDeletion() async throws {
    let source = source(item: 0)
    let agent = SampleAgent(model: source)
    let recorder = Recorder<SampleSnapshot>()
    let task = recorder.collect(await agent.updates())
    defer { task.cancel() }
    try await eventually { recorder.last?.isUpToDate == true }
    let firstID = try #require(source.items.first?.identifier)
    let secondID = try #require((await agent.appendCopy()).value)
    try await eventually {
      recorder.last?.items.last?.id == secondID && recorder.last?.items.last?.isLoading == false
    }
    #expect(source.updateItem(secondID, changes: ["metricValue": "0"]))
    try await eventually { recorder.last?.items.last?.hasError == true }
    #expect(source.error && !source.items[0].error && source.items[1].error)
    #expect(recorder.last?.items.first?.hasError == false)
    #expect(recorder.last?.validationError == "Metric must be a positive number.")

    #expect((await agent.reorder(ids: [secondID, firstID], expectedArrangement: [firstID, secondID])).succeeded)
    try await eventually { recorder.last?.items.first?.id == secondID }
    #expect(recorder.last?.items.first?.hasError == true)
    #expect(recorder.last?.items.last?.hasError == false)
    #expect(source.updateItem(firstID, changes: ["sampleName": ""]))
    try await eventually { recorder.last?.items.allSatisfy(\.hasError) == true }
    #expect(source.updateItem(secondID, changes: ["metricValue": "42.00"]))
    try await eventually { recorder.last?.items.first?.hasError == false }
    #expect(recorder.last?.items.last?.hasError == true && source.error)

    #expect((await agent.delete(id: firstID)).succeeded)
    try await eventually { recorder.last?.validationError == "" }
    #expect(!source.error && recorder.last?.items.first?.hasError == false)
    await agent.finish()
  }

  @Test func complexLegacyCallbacksDoNotProduceSnapshots() async throws {
    let source = source()
    let agent = SampleAgent(model: source)
    let recorder = Recorder<SampleSnapshot>()
    let task = recorder.collect(await agent.updates())
    defer { task.cancel() }
    try await eventually { recorder.last?.isUpToDate == true }
    let initial = try #require(recorder.last)
    let count = recorder.values.count
    for _ in 0..<5 { source.simulateLegacyTick() }
    #expect(source.auditSequence == 5)
    #expect(source.estimatedOverhead == NSDecimalNumber(string: "1.05"))
    #expect(source.diagnostics["sequence"] == "5")
    let item = try #require(source.items.first)
    #expect(item.serverRevision == 5)
    #expect(item.estimatedWork == NSDecimalNumber(string: "0.15"))
    #expect(item.rawAttributes["revision"] == "5")
    #expect(initial.items.first?.metricValue == "42.00")
    #expect((await agent.selectKind(.sequence)).succeeded)
    try await eventually { recorder.last?.kind == .sequence }
    #expect(recorder.values.count == count + 1)
    await agent.finish()
    await task.value
    #expect(source.listenerCount == 0)
  }

  @Test func usefulChangesStillArriveOnceAfterLegacyNoise() async throws {
    let source = source()
    let agent = SampleAgent(model: source)
    let recorder = Recorder<SampleSnapshot>()
    let task = recorder.collect(await agent.updates())
    defer { task.cancel() }
    try await eventually { recorder.last?.isUpToDate == true }
    let previous = try #require(recorder.last)
    let count = recorder.values.count
    source.simulateLegacyTick()
    source.simulateMetricTick()
    source.simulateLegacyTick()
    try await eventually { recorder.last?.items.first?.metricValue == "42.25" }
    await agent.finish()
    await task.value
    #expect(recorder.values.count == count + 1)
    #expect(previous.items.first?.metricValue == "42.00")
    #expect(recorder.last?.items.first?.metricValue == "42.25")
  }

  @Test func secondSubscriptionIsClosedWithoutAffectingTheConsumer() async throws {
    let source = source()
    let agent = SampleAgent(model: source)
    let recorder = Recorder<SampleSnapshot>()
    let task = recorder.collect(await agent.updates())
    defer { task.cancel() }
    try await eventually { recorder.last?.isUpToDate == true }
    let count = recorder.values.count
    source.simulateMetricTick()
    var second = await agent.updates().makeAsyncIterator()
    #expect(await second.next() == nil)
    try await eventually { recorder.last?.items.first?.metricValue == "42.25" }
    #expect(recorder.values.count == count + 1 && source.listenerCount == 1)
    await agent.finish()
    await task.value
  }

  @Test func slowConsumerReceivesLatestValueAndFinishDetachesListener() async throws {
    let source = source()
    let agent = SampleAgent(model: source)
    var iterator = await agent.updates().makeAsyncIterator()
    var initial = try #require(await iterator.next())
    while !initial.isUpToDate { initial = try #require(await iterator.next()) }
    for _ in 0..<3 { source.simulateMetricTick() }
    let latest = await iterator.next()
    #expect(initial.items.first?.metricValue == "42.00")
    #expect(latest?.items.first?.metricValue == "42.75")
    await agent.finish()
    #expect(source.listenerCount == 0)
    #expect(await iterator.next() == nil)
  }

  @Test func consumerCancellationStopsSourceAndCannotReopenAgent() async throws {
    let source = source()
    let agent = SampleAgent(model: source)
    let recorder = Recorder<SampleSnapshot>()
    let task = recorder.collect(await agent.updates())
    try await eventually { recorder.last?.isUpToDate == true }
    #expect(source.listenerCount == 1)
    task.cancel()
    await task.value
    try await eventually { source.listenerCount == 0 && !source.isActive }
    var closed = await agent.updates().makeAsyncIterator()
    #expect(await closed.next() == nil && source.listenerCount == 0)
  }

  @Test func finishingOneAgentPreservesAnotherAgentOnTheSameModel() async throws {
    let source = source()
    let firstAgent = SampleAgent(model: source)
    let secondAgent = SampleAgent(model: source)
    let first = Recorder<SampleSnapshot>()
    let second = Recorder<SampleSnapshot>()
    let firstTask = first.collect(await firstAgent.updates())
    let secondTask = second.collect(await secondAgent.updates())
    defer { firstTask.cancel(); secondTask.cancel() }
    try await eventually { first.last?.isUpToDate == true && second.last?.isUpToDate == true }
    #expect(source.listenerCount == 2)
    await firstAgent.finish()
    await firstTask.value
    #expect(source.listenerCount == 1 && source.isActive && source.isUpToDate)
    source.simulateMetricTick()
    try await eventually { second.last?.items.first?.metricValue == "42.25" }
    #expect((await secondAgent.appendCopy()).value != nil)
    await secondAgent.finish()
    await secondTask.value
    #expect(source.listenerCount == 0 && !source.isActive && !source.isUpToDate)
  }

  @Test func deletingPendingItemIgnoresLateCompletion() async throws {
    let source = source(item: 0.12)
    let agent = SampleAgent(model: source)
    let recorder = Recorder<SampleSnapshot>()
    let task = recorder.collect(await agent.updates())
    defer { task.cancel() }
    try await eventually { recorder.last?.isUpToDate == true }
    let id = try #require((await agent.appendCopy()).value)
    let pending = try #require(source.items.last)
    #expect(pending.isLoading)
    #expect((await agent.delete(id: id)).succeeded)
    try await Task.sleep(for: .milliseconds(180))
    #expect(source.items.count == 1)
    #expect(recorder.last?.items.contains { $0.id == id } == false)
    #expect(pending.isLoading)
  }

  @Test func viewModelCommitsCommandsAndPreservesLiveValuesAcrossDragAndEditing() async throws {
    let source = source(item: 0.02)
    let viewModel = SampleBoardViewModel(agent: SampleAgent(model: source))
    let task = Task { await viewModel.observe() }
    defer { task.cancel() }
    try await eventually { viewModel.canInteract && !viewModel.cards.isEmpty }
    for count in 2...3 {
      #expect(await viewModel.appendCopy() != nil)
      try await eventually {
        viewModel.cards.count == count && viewModel.cards.last?.isLoading == false
      }
    }
    let originalIDs = viewModel.cards.map(\.id)
    source.simulateMetricTick()
    try await eventually { viewModel.cards.allSatisfy { $0.metricValue == "42.25" } }
    #expect(viewModel.cards.map(\.id) == originalIDs)
    #expect(source.items.map(\.identifier) == originalIDs)
    await viewModel.move(id: originalIDs[0], to: originalIDs[2], expectedArrangement: originalIDs)
    #expect(viewModel.cards.map(\.id) == [originalIDs[1], originalIDs[2], originalIDs[0]])
    #expect(source.items.map(\.identifier) == viewModel.cards.map(\.id))
    #expect(viewModel.errorMessage == nil)
    let draft = try #require(viewModel.cards.first)
    source.simulateMetricTick()
    try await eventually { viewModel.cards.first?.metricValue == "42.50" }
    var edit = SampleItemDraft(card: draft)
    edit.sampleName = "StringFold"
    #expect(await viewModel.update(original: draft, draft: edit))
    try await eventually { viewModel.cards.first?.sampleName == "StringFold" }
    #expect(viewModel.cards.first?.metricValue == "42.50")
    await viewModel.select(LayoutCatalog.stagedMatrix)
    try await eventually { viewModel.layout == LayoutCatalog.stagedMatrix }
    #expect(source.layoutTag == LayoutCatalog.stagedMatrix.id)
    await viewModel.delete(id: draft.id)
    try await eventually { viewModel.cards.count == 2 }
    #expect(!source.items.contains { $0.identifier == draft.id })
    task.cancel()
    await task.value
    #expect(source.listenerCount == 0)
  }

  @Test func newAgentsResumeModelLoadingWithoutResurrectingCancelledWork() async throws {
    let source = source(load: 0.08, item: 0.08)
    let agent = SampleAgent(model: source)
    let recorder = Recorder<SampleSnapshot>()
    let initial = recorder.collect(await agent.updates())
    try await eventually { recorder.last != nil }
    initial.cancel()
    await initial.value
    try await eventually { !source.isActive }
    try await Task.sleep(for: .milliseconds(120))
    #expect(source.items.isEmpty)
    let reloadedAgent = SampleAgent(model: source)
    let reloaded = recorder.collect(await reloadedAgent.updates())
    try await eventually { recorder.last?.isUpToDate == true }
    let id = try #require((await reloadedAgent.appendCopy()).value)
    reloaded.cancel()
    await reloaded.value
    try await eventually { !source.isActive }
    try await Task.sleep(for: .milliseconds(120))
    #expect(source.items.last?.isLoading == true)
    let resumedAgent = SampleAgent(model: source)
    let resumed = recorder.collect(await resumedAgent.updates())
    defer { resumed.cancel() }
    try await eventually {
      recorder.last?.items.last?.id == id && recorder.last?.items.last?.isLoading == false
    }
    #expect(source.items.count == 2)
  }

  @Test func immediatelyCancelledObservationLeavesNoListener() async {
    let source = source(load: 0.08)
    let viewModel = SampleBoardViewModel(agent: SampleAgent(model: source))
    let observation = Task { await viewModel.observe() }
    observation.cancel()
    await observation.value
    #expect(source.listenerCount == 0 && !source.isActive)
  }

  @Test func cancellingConsumerReleasesAgentRetainedByModel() async throws {
    let source = source()
    var agent: SampleAgent? = SampleAgent(model: source)
    weak let weakAgent = agent
    let recorder = Recorder<SampleSnapshot>()
    let stream = try #require(await agent?.updates())
    let task = recorder.collect(stream)
    try await eventually { recorder.last?.isUpToDate == true }
    agent = nil
    #expect(weakAgent != nil) // The SDK owns its registered listener until observation ends.
    task.cancel()
    await task.value
    try await eventually { weakAgent == nil && source.listenerCount == 0 }
    #expect(!source.isActive)
  }
}
