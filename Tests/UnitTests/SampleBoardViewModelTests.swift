import Foundation
import Observation
import Testing

@testable import JavaSwiftBridgeLab

@MainActor
struct SampleBoardViewModelTests {
  @Test func genericStateContractTracksObservationAndActions() async throws {
    let source = TestSampleAgent()
    let viewModel = SampleBoardViewModel(agent: source)
    try await verifyContracts(actions: viewModel, state: viewModel, source: source)
  }

  private func verifyContracts<Actions: SampleBoardActions, Data: SampleBoardState>(
    actions: Actions, state: Data, source: TestSampleAgent
  ) async throws {
    #expect(state.isLoading)
    let observation = Task { await actions.observe() }
    defer { observation.cancel() }
    try await eventually { !state.isLoading }
    #expect(state.cards.count == 1)
    #expect(state.layout == LayoutCatalog.sequence)
    let invalidation = Invalidation()
    withObservationTracking {
      _ = state.cards
    } onChange: {
      Task { @MainActor in invalidation.changed = true }
    }
    let original = try #require(state.cards.first)
    let changed = original.withMetric("90000.00")
    source.send(TestSampleAgent.state([changed]))
    try await eventually { invalidation.changed && state.cards.first?.metricValue == "90000.00" }
    #expect(await actions.appendCopy() == source.appendedID)
    #expect(source.commands == [.append])
  }

  @Test func pendingDropBlocksConflictingCommandsAndRejectionKeepsSourceArrangement() async throws {
    let cards = [SampleItemSnapshot.sample, SampleItemSnapshot.sample]
    let source = TestSampleAgent(cards: cards)
    source.holdsReorder = true
    let viewModel = SampleBoardViewModel(agent: source)
    let observation = Task { await viewModel.observe() }
    defer { observation.cancel() }
    try await eventually { !viewModel.isLoading }
    let commit = Task {
      await viewModel.move(id: cards[0].id, to: cards[1].id, expectedArrangement: cards.map(\.id))
    }
    try await eventually { source.pendingReorder != nil }
    #expect(viewModel.isPerformingCommand)
    #expect(await viewModel.appendCopy() == nil)
    await viewModel.delete(id: cards[1].id)
    await viewModel.move(id: cards[1].id, by: -1)
    source.pendingReorder?.resume(returning: false)
    source.pendingReorder = nil
    await commit.value
    #expect(viewModel.cards == cards)
    #expect(!viewModel.isPerformingCommand)
    #expect(source.commands == [.reorder(cards.reversed().map(\.id))])
  }

  @MainActor private final class Invalidation { var changed = false }
  @Test func emptySnapshotClearsOldCardsWithoutLoadingForever() async throws {
    let source = TestSampleAgent()
    let vm = SampleBoardViewModel(agent: source)
    let task = Task { await vm.observe() }
    defer { task.cancel() }
    try await eventually { !vm.isLoading }
    source.send(TestSampleAgent.state([], kind: .radial))
    try await eventually { vm.cards.isEmpty && vm.layout == LayoutCatalog.radial }
    #expect(!vm.isLoading && vm.canInteract)
  }

  @Test func unknownKindAndOversizedSnapshotShowErrorAndBlockCommands() async throws {
    let source = TestSampleAgent()
    let vm = SampleBoardViewModel(agent: source)
    let task = Task { await vm.observe() }
    defer { task.cancel() }
    try await eventually { !vm.isLoading }
    source.send(
      SampleSnapshot(
        isUpToDate: true, isActive: true, validationError: "",
        kind: nil, items: []))
    try await eventually { vm.errorMessage != nil }
    #expect(vm.cards.isEmpty && !vm.canInteract)
    source.send(TestSampleAgent.state([.sample]))
    try await eventually { vm.canInteract && vm.errorMessage == nil }
    source.send(
      SampleSnapshot(
        isUpToDate: true, isActive: true, validationError: "",
        kind: .radial,
        items: (0..<9).map { _ in SampleItemSnapshot.sample }))
    try await eventually { vm.errorMessage == SampleFailure.invalidSnapshot.message }
    #expect(vm.cards.isEmpty && !vm.canInteract)
  }

  @Test func commandRejectionIsVisibleAndNextSuccessClearsIt() async throws {
    let source = TestSampleAgent()
    let vm = SampleBoardViewModel(agent: source)
    let task = Task { await vm.observe() }
    defer { task.cancel() }
    try await eventually { !vm.isLoading }
    source.acceptsCommands = false
    #expect(await vm.appendCopy() == nil)
    #expect(vm.errorMessage == SampleFailure.rejected.message)
    source.acceptsCommands = true
    #expect(await vm.appendCopy() != nil)
    #expect(vm.errorMessage == nil)
  }

  @Test func nativePayloadContainsOnlyIdentitiesAndRoundTrips() throws {
    let payload = SampleCardTransfer(editorID: UUID(), cardID: UUID(), arrangement: [UUID(), UUID()])
    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(SampleCardTransfer.self, from: data)
    #expect(decoded.editorID == payload.editorID)
    #expect(decoded.cardID == payload.cardID)
    #expect(decoded.arrangement == payload.arrangement)
    let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(keys.keys) == ["editorID", "cardID", "arrangement"])
  }
}
