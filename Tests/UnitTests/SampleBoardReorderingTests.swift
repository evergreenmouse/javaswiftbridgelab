import Foundation
import Testing

@testable import JavaSwiftBridgeLab

@MainActor
struct SampleBoardReorderingTests {
  private func cards(_ count: Int) -> [SampleItemSnapshot] {
    (0..<count).map { SampleItemSnapshot.make(sampleName: "Entry \($0)") }
  }

  @Test func insertionWorksInBothDirectionsForEveryPairOfOccupiedSlots() async throws {
    let original = cards(8)
    for layout in LayoutCatalog.all {
      for sourceIndex in 0..<8 {
        for destination in 0..<8 {
          let agent = TestSampleAgent(cards: original, kind: layout.kind)
          let editor = SampleBoardViewModel(agent: agent)
          let observation = Task { await editor.observe() }
          defer { observation.cancel() }
          try await eventually { !editor.isLoading }
          await editor.move(
            id: original[sourceIndex].id, to: original[destination].id,
            expectedArrangement: original.map(\.id))
          var expected = original
          expected.insert(expected.remove(at: sourceIndex), at: destination)
          #expect(editor.cards == expected)
          #expect(!editor.isPerformingCommand)
          #expect(agent.commands == (sourceIndex == destination ? [] : [.reorder(expected.map(\.id))]))
        }
      }
    }
  }

  @Test func unknownSourceDestinationAndOutOfRangeAccessibilityMoveDoNothing() async throws {
    let original = cards(3)
    let agent = TestSampleAgent(cards: original)
    let editor = SampleBoardViewModel(agent: agent)
    let observation = Task { await editor.observe() }
    defer { observation.cancel() }
    try await eventually { !editor.isLoading }
    await editor.move(id: UUID(), to: original[1].id, expectedArrangement: original.map(\.id))
    await editor.move(id: original[0].id, to: UUID(), expectedArrangement: original.map(\.id))
    await editor.move(id: original[0].id, by: -1)
    await editor.move(id: original[2].id, by: 1)
    #expect(editor.cards == original && agent.commands.isEmpty)
  }

  @Test func loadingSourceCannotBeMoved() async throws {
    let original = [SampleItemSnapshot.make(isLoading: true), SampleItemSnapshot.sample]
    let agent = TestSampleAgent(cards: original)
    let editor = SampleBoardViewModel(agent: agent)
    let observation = Task { await editor.observe() }
    defer { observation.cancel() }
    try await eventually { !editor.isLoading }
    await editor.move(id: original[0].id, to: original[1].id, expectedArrangement: original.map(\.id))
    #expect(editor.cards == original && agent.commands.isEmpty)
  }

  @Test func finalCardCannotBeDeletedInAnyLayout() async throws {
    for layout in LayoutCatalog.all {
      let agent = TestSampleAgent(kind: layout.kind)
      let editor = SampleBoardViewModel(agent: agent)
      let observation = Task { await editor.observe() }
      defer { observation.cancel() }
      try await eventually { !editor.isLoading }
      let card = try #require(editor.cards.first)
      #expect(!editor.canDelete(id: card.id))
      await editor.delete(id: card.id)
      #expect(editor.cards.count == 1 && agent.commands.isEmpty)
    }
  }

  @Test func externalArrangementRejectsStaleDropAndKeepsLatestSourceArrangement() async throws {
    let original = cards(3)
    let agent = TestSampleAgent(cards: original)
    let editor = SampleBoardViewModel(agent: agent)
    let observation = Task { await editor.observe() }
    defer { observation.cancel() }
    try await eventually { !editor.isLoading }
    let authoritative = [original[2], original[1], original[0]]
    agent.send(TestSampleAgent.state(authoritative))
    try await eventually { editor.cards == authoritative }
    await editor.move(id: original[0].id, to: original[2].id, expectedArrangement: original.map(\.id))
    #expect(editor.cards == authoritative && agent.commands.isEmpty)
    #expect(editor.errorMessage == SampleFailure.conflict.message)
  }

  @Test func metricUpdateBeforeDropPreservesLiveFields() async throws {
    var original = cards(3)
    let agent = TestSampleAgent(cards: original)
    let editor = SampleBoardViewModel(agent: agent)
    let observation = Task { await editor.observe() }
    defer { observation.cancel() }
    try await eventually { !editor.isLoading }
    let expectedArrangement = original.map(\.id)
    original[0] = original[0].withMetric("90000.00")
    agent.send(TestSampleAgent.state(original))
    try await eventually { editor.cards.first?.metricValue == "90000.00" }
    await editor.move(id: original[0].id, to: original[2].id, expectedArrangement: expectedArrangement)
    #expect(editor.cards == [original[1], original[2], original[0]])
    #expect(editor.errorMessage == nil)
  }

  @Test func sourceLayoutChangeKeepsValuesAndVoiceOverMoveUsesSameCommand() async throws {
    let original = cards(8)
    let agent = TestSampleAgent(cards: original)
    let editor = SampleBoardViewModel(agent: agent)
    let observation = Task { await editor.observe() }
    defer { observation.cancel() }
    try await eventually { !editor.isLoading }
    for layout in LayoutCatalog.all {
      agent.send(TestSampleAgent.state(original, kind: layout.kind))
      try await eventually { editor.layout == layout && editor.cards == original }
      await editor.move(id: original[0].id, by: 2)
      #expect(editor.cards == [original[1], original[2], original[0]] + original.dropFirst(3))
    }
  }

  @Test func deletionDuringDragRejectsStaleDropWithoutLosingNewData() async throws {
    let original = cards(2)
    let agent = TestSampleAgent(cards: original)
    let editor = SampleBoardViewModel(agent: agent)
    let observation = Task { await editor.observe() }
    defer { observation.cancel() }
    try await eventually { !editor.isLoading }
    agent.send(TestSampleAgent.state([original[1]]))
    try await eventually { editor.cards == [original[1]] }
    await editor.move(id: original[0].id, to: original[1].id, expectedArrangement: original.map(\.id))
    #expect(editor.cards == [original[1]] && agent.commands.isEmpty)
    #expect(editor.errorMessage == SampleFailure.conflict.message)
  }

  @Test func acceptedArrangementRemainsVisibleUntilSourceSnapshotArrives() async throws {
    let original = cards(3)
    let agent = TestSampleAgent(cards: original)
    let editor = SampleBoardViewModel(agent: agent)
    let observation = Task { await editor.observe() }
    defer { observation.cancel() }
    try await eventually { !editor.isLoading }
    await editor.move(id: original[0].id, to: original[2].id, expectedArrangement: original.map(\.id))
    let accepted = [original[1], original[2], original[0].withMetric("90000.00")]
    #expect(agent.snapshot.items == original)
    #expect(editor.cards.map(\.id) == accepted.map(\.id))
    agent.send(TestSampleAgent.state(accepted))
    try await eventually { editor.cards.last?.metricValue == "90000.00" }
    #expect(editor.cards == accepted && editor.errorMessage == nil)
  }

  @Test func delayedReplyDoesNotOverwriteNewerStructuralSnapshot() async throws {
    let original = cards(3)
    let agent = TestSampleAgent(cards: original)
    agent.holdsReorder = true
    let editor = SampleBoardViewModel(agent: agent)
    let observation = Task { await editor.observe() }
    defer { observation.cancel() }
    try await eventually { !editor.isLoading }
    let command = Task {
      await editor.move(id: original[0].id, to: original[2].id, expectedArrangement: original.map(\.id))
    }
    try await eventually { agent.pendingReorder != nil }
    agent.send(TestSampleAgent.state([original[1]]))
    try await eventually { editor.cards == [original[1]] }
    agent.pendingReorder?.resume(returning: true)
    agent.pendingReorder = nil
    await command.value
    #expect(editor.cards == [original[1]] && !editor.isPerformingCommand)
  }
}
