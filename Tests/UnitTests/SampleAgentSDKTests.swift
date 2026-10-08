import Foundation
import LegacySampleMock
import Testing

@testable import JavaSwiftBridgeLab

/// Instruments the actual Objective-C model; no parallel model contract or field implementation.
private final class SDKModel: CompositeSampleModel {
  enum Command: Equatable {
    case append
    case delete(UUID)
    case update(UUID, [String: String])
    case reorder([UUID])
    case layout(String)
  }
  var registrations = 0
  var removals = 0
  var commands: [Command] = []
  var acceptsCommands = true

  /// Snapshot projection must read even unannotated SDK getters on MainActor.
  override var layoutTag: String {
    MainActor.assertIsolated()
    return super.layoutTag
  }
  weak var registeredListener: (any CompositeSampleModelListener)?

  override func addListener(_ listener: any CompositeSampleModelListener) {
    MainActor.assertIsolated()
    registrations += 1
    registeredListener = listener
    super.addListener(listener)
  }
  override func removeListener(_ listener: any CompositeSampleModelListener) {
    MainActor.assertIsolated()
    removals += 1
    super.removeListener(listener)
    if registeredListener === listener { registeredListener = nil }
  }
  override func appendCopy() -> SampleItemModel? {
    MainActor.assertIsolated()
    commands.append(.append)
    return acceptsCommands ? super.appendCopy() : nil
  }
  override func deleteItem(_ id: UUID) -> Bool {
    MainActor.assertIsolated()
    commands.append(.delete(id))
    return acceptsCommands && super.deleteItem(id)
  }
  override func updateItem(_ id: UUID, changes: [String: String]) -> Bool {
    MainActor.assertIsolated()
    commands.append(.update(id, changes))
    return acceptsCommands && super.updateItem(id, changes: changes)
  }
  override func reorderItems(_ ids: [UUID]) -> Bool {
    MainActor.assertIsolated()
    commands.append(.reorder(ids))
    return acceptsCommands && super.reorderItems(ids)
  }
  override func selectLayoutTag(_ marker: String) {
    MainActor.assertIsolated()
    commands.append(.layout(marker))
    if acceptsCommands { super.selectLayoutTag(marker) }
  }
}

@MainActor
struct SampleAgentSDKTests {
  enum Callback: String, CaseIterable, Sendable {
    case change, upToDate, inactive, state, notUpToDate, layoutTag
  }

  private struct Timeout: Error {}
  private func eventually(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !condition() {
      guard ContinuousClock.now < deadline else {
        Issue.record("Timed out waiting for a direct SDK state transition")
        throw Timeout()
      }
      try await Task.sleep(for: .milliseconds(5))
    }
  }

  /// Load the real SDK before attaching the agent to make callback and command checks deterministic.
  private func model() async throws -> SDKModel {
    let model = SDKModel(loadDelay: 0, itemDelay: 0, metricInterval: 0)
    let preload = SampleAgent(model: model)
    let preparation = await preload.updates()
    try await eventually { model.isUpToDate }
    let id = try #require(model.items.first?.identifier)
    #expect(model.updateItem(id, changes: [
      "sampleName": "StringFold", "metricValue": "3000.00", "runtime": "SWIFT",
      "iterations": "-10", "variant": "NATIVE V1",
    ]))
    model.selectLayoutTag("sequence")
    await preload.finish()
    withExtendedLifetime(preparation) {}
    model.registrations = 0
    model.removals = 0
    model.commands = []
    return model
  }

  @Test(arguments: Callback.allCases)
  func eachObjCSelectorOnMainActorRefreshesSnapshot(_ callback: Callback) async throws {
    let model = try await model()
    let agent = SampleAgent(model: model)
    let stream = await agent.updates()
    var latest: SampleSnapshot?
    let consumer = Task { @MainActor in
      for await value in stream { latest = value }
    }
    defer { consumer.cancel() }
    try await eventually { latest?.items.first?.metricValue == "3000.00" }
    // KVC changes a readonly SDK field silently; only the tested selector announces it.
    model.items[0].setValue("4000.00", forKey: "metricValue")
    Self.emit(callback, to: try #require(model.registeredListener))
    try await eventually { latest?.items.first?.metricValue == "4000.00" }
    #expect(model.listenerCount == 1 && model.registrations == 1)
    await agent.finish()
    await consumer.value
    #expect(model.listenerCount == 0 && model.removals == 1)
  }

  /// Invoke selectors on the same executor required by the real legacy models.
  private static func emit(_ callback: Callback, to listener: any CompositeSampleModelListener) {
    MainActor.assertIsolated()
    switch callback {
    case .change: listener.onCompositeSampleModelChange()
    case .upToDate: listener.onCompositeSampleModelUpToDate()
    case .inactive: listener.onCompositeSampleModelInactive()
    case .state: listener.onCompositeSampleModelStateChange()
    case .notUpToDate: listener.onCompositeSampleModelNotUpToDate()
    case .layoutTag: listener.onCompositeSampleModelLayoutTagChange()
    }
  }

  @Test func oldListenerCallbacksCannotReachTheNextScenesAgent() async throws {
    let model = try await model()
    let firstAgent = SampleAgent(model: model)
    var first = await firstAgent.updates().makeAsyncIterator()
    _ = await first.next()
    let oldListener = try #require(model.registeredListener)
    model.items[0].setValue("1.00", forKey: "metricValue")
    Self.emit(.change, to: oldListener)
    await firstAgent.finish()
    while await first.next() != nil {}

    model.items[0].setValue("5000.00", forKey: "metricValue")
    let secondAgent = SampleAgent(model: model)
    var second = await secondAgent.updates().makeAsyncIterator()
    #expect(await second.next()?.items.first?.metricValue == "5000.00")
    // A copied SDK listener array can still reference the old agent after removal.
    model.items[0].setValue("1.00", forKey: "metricValue")
    Self.emit(.change, to: oldListener)
    model.items[0].setValue("6000.00", forKey: "metricValue")
    Self.emit(.change, to: try #require(model.registeredListener))
    #expect(await second.next()?.items.first?.metricValue == "6000.00")
    await secondAgent.finish()
    #expect(await second.next() == nil)
    #expect(model.registrations == 2 && model.removals == 2 && model.listenerCount == 0)
  }

  @Test func agentReadsSDKAndMapsOnlyChangedCommandFields() async throws {
    let model = try await model()
    let agent = SampleAgent(model: model)
    var iterator = await agent.updates().makeAsyncIterator()
    let snapshot = try #require(await iterator.next())
    let item = try #require(snapshot.items.first)
    #expect(snapshot.isActive && snapshot.isUpToDate && snapshot.kind == .sequence)
    #expect(item.sampleName == "StringFold" && item.runtime == .swift && item.metricValue == "3000.00")
    let copy = try #require((await agent.appendCopy()).value)
    #expect(copy != item.id)
    let changes = SampleItemChanges(sampleName: "ArrayMap", runtime: .java)
    #expect((await agent.update(id: item.id, changes: changes)).succeeded)
    let arrangement = [item.id, copy]
    #expect((await agent.reorder(ids: arrangement, expectedArrangement: arrangement)).succeeded)
    #expect((await agent.selectKind(.matrix)).succeeded)
    model.acceptsCommands = false
    #expect((await agent.delete(id: item.id)).succeeded == false)
    #expect(model.commands == [
      .append, .update(item.id, ["sampleName": "ArrayMap", "runtime": "JAVA"]),
      .reorder(arrangement), .layout(LayoutCatalog.matrix.id), .delete(item.id),
    ])
    try await eventually { model.items.allSatisfy { !$0.isLoading } }
    var changed = try #require(await iterator.next())
    while changed.kind != .matrix || changed.items.last?.isLoading != false {
      changed = try #require(await iterator.next())
    }
    #expect(changed.kind == .matrix && changed.items.count == 2)
    #expect(changed.items.first?.metricValue == item.metricValue)
    // Legacy callbacks contain no additional useful fields and must remain deduplicated.
    for _ in 0..<10 { model.simulateLegacyTick() }
    await agent.finish()
    #expect(await iterator.next() == nil)
  }

  @Test func replacementWithSameIDReadsCurrentSDKItem() async throws {
    let model = try await model()
    let agent = SampleAgent(model: model)
    var iterator = await agent.updates().makeAsyncIterator()
    _ = await iterator.next()
    let old = model.items[0]
    let replacement = SampleItemModel()
    replacement.setValue(old.identifier as NSUUID, forKey: "identifier")
    model.setValue([replacement], forKey: "items")
    old.setValue("1.00", forKey: "metricValue")
    replacement.setValue("4000.00", forKey: "metricValue")
    model.simulateLegacyTick()
    let latest = try #require(await iterator.next())
    #expect(latest.items.first?.id == old.identifier)
    #expect(latest.items.first?.metricValue == "4000.00")
    #expect(model.listenerCount == 1)
    await agent.finish()
    #expect(model.listenerCount == 0)
    #expect(await iterator.next() == nil)
  }

  @Test func registrationUsesAgentDirectlyAndFinishIsTerminal() async throws {
    let model = try await model()
    let agent = SampleAgent(model: model)
    var first = await agent.updates().makeAsyncIterator()
    #expect(await first.next() != nil)
    var second = await agent.updates().makeAsyncIterator()
    #expect(await second.next() == nil)
    #expect(model.registeredListener === agent)
    #expect(model.registrations == 1 && model.listenerCount == 1)
    await agent.finish()
    await agent.finish()
    #expect(await first.next() == nil)
    #expect(await second.next() == nil)
    var closed = await agent.updates().makeAsyncIterator()
    #expect(await closed.next() == nil)
    #expect(model.registrations == 1 && model.removals == 1 && model.listenerCount == 0)

    // Even an active source shared with another agent cannot reopen the finished one.
    let nextAgent = SampleAgent(model: model)
    let nextStream = await nextAgent.updates()
    let result = await agent.appendCopy()
    if case .failure(let failure) = result { #expect(failure == .inactive) }
    else { Issue.record("A finished agent accepted a command") }
    #expect(model.commands.isEmpty)
    await nextAgent.finish()
    withExtendedLifetime(nextStream) {}
  }

  @Test func finishBeforeFirstSubscriptionNeverRegisters() async throws {
    let model = try await model()
    let agent = SampleAgent(model: model)
    await agent.finish()
    var stream = await agent.updates().makeAsyncIterator()
    #expect(await stream.next() == nil)
    #expect(model.registrations == 0 && model.removals == 0 && model.listenerCount == 0)
  }

  @Test func malformedRawValuesAndDuplicateIDsProduceFailureWithoutCrashing() async throws {
    let model = try await model()
    let original = model.items[0]
    let duplicate = SampleItemModel()
    duplicate.setValue(original.identifier as NSUUID, forKey: "identifier")
    model.setValue([original, duplicate], forKey: "items")
    let agent = SampleAgent(model: model)
    var iterator = await agent.updates().makeAsyncIterator()
    #expect(await iterator.next()?.failure == .invalidSnapshot)
    model.setValue([original], forKey: "items")
    original.setValue("UNKNOWN", forKey: "runtime")
    model.simulateLegacyTick()
    #expect(await iterator.next()?.failure == .unsupportedValue("UNKNOWN"))
    original.setValue("JAVA", forKey: "runtime")
    model.setValue("unknown-kind", forKey: "layoutTag")
    model.simulateLegacyTick()
    let unsupported = try #require(await iterator.next())
    #expect(unsupported.failure == .unsupportedValue("unknown-kind"))
    #expect(unsupported.kind == nil && unsupported.items.isEmpty)
    await agent.finish()
  }

  @Test func outdatedExpectedArrangementRejectsReorderBeforeCallingSDK() async throws {
    let model = try await model()
    let agent = SampleAgent(model: model)
    let stream = await agent.updates()
    let result = await agent.reorder(
      ids: model.items.map(\.identifier), expectedArrangement: [UUID()])
    #expect(result.succeeded == false && model.commands.isEmpty)
    if case .failure(let failure) = result { #expect(failure == .conflict) }
    await agent.finish()
    withExtendedLifetime(stream) {}
  }
}
