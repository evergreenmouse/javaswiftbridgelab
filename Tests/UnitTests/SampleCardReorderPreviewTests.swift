import Foundation
import Testing

@testable import JavaSwiftBridgeLab

@MainActor
struct SampleCardReorderPreviewTests {
  @Test func cancelledPreviewKeepsTheLiftedIdentityUntilUIKitFinishesLanding() {
    let item = SampleItemSnapshot.make()
    let interaction = SampleBoardInteractionState()
    interaction.reorder = SampleCardReorderPreview(payload: SampleCardTransfer(
      editorID: interaction.editorID, cardID: item.id, arrangement: [item.id]))
    interaction.beginDrag(cardID: item.id, index: 0)
    let session = interaction.drag.session!
    interaction.beginLanding()
    interaction.reorder = nil
    #expect(interaction.isBusy && interaction.drag.isLanding)
    #expect(interaction.drag.session?.cardID == item.id)
    interaction.endDrag(sessionID: session.id)
    #expect(!interaction.isBusy && interaction.drag.session == nil)
    #expect(interaction.isEditing)
  }

  @Test func obsoleteUIKitCompletionCannotRevealANewerDraggedCard() {
    let interaction = SampleBoardInteractionState()
    interaction.beginDrag(cardID: UUID(), index: 0)
    let oldID = interaction.drag.session!.id
    let currentCardID = UUID()
    interaction.beginDrag(cardID: currentCardID, index: 1)
    let currentID = interaction.drag.session!.id
    interaction.endDrag(sessionID: oldID)
    #expect(interaction.isBusy && interaction.drag.session?.cardID == currentCardID)
    interaction.endDrag(sessionID: currentID)
    #expect(!interaction.isBusy)
  }

  @Test func hoverTracksTheSameCardAcrossSeveralOccupiedPositions() {
    let original = (0..<5).map { SampleItemSnapshot.make(sampleName: "Entry \($0)") }
    var preview = SampleCardReorderPreview(payload: SampleCardTransfer(
      editorID: UUID(), cardID: original[0].id, arrangement: original.map(\.id)))
    preview.move(to: 2)
    #expect(preview.arrangement == [original[1], original[2], original[0], original[3], original[4]].map(\.id))
    preview.move(to: 4)
    #expect(preview.arrangement == Array(original.dropFirst()).map(\.id) + [original[0].id])
    preview.move(to: 0)
    #expect(preview.arrangement == original.map(\.id))
    preview.move(to: 0)
    preview.move(to: 100)
    #expect(preview.arrangement == original.map(\.id))
    #expect(preview.payload.arrangement == original.map(\.id))
  }

  @Test func previewUsesLatestFieldsAndErrorsWithoutChangingTheSourceArrangement() {
    let original = [SampleItemSnapshot.make(), SampleItemSnapshot.make()]
    var preview = SampleCardReorderPreview(payload: SampleCardTransfer(
      editorID: UUID(), cardID: original[0].id, arrangement: original.map(\.id)))
    preview.move(to: 1)
    let changed = SampleItemSnapshot.make(
      id: original[0].id, sampleName: "Updated", metricValue: "90000", hasError: true)
    let latest = [changed, original[1]]
    #expect(preview.cards(from: latest) == [original[1], changed])
    #expect(latest.map(\.id) == original.map(\.id))
    #expect(preview.cards(from: latest).last?.hasError == true)
  }

  @Test func structuralChangesImmediatelyUseTheAuthoritativeSourceCards() {
    let original = [SampleItemSnapshot.make(), SampleItemSnapshot.make()]
    var preview = SampleCardReorderPreview(payload: SampleCardTransfer(
      editorID: UUID(), cardID: original[0].id, arrangement: original.map(\.id)))
    preview.move(to: 1)
    for changed in [original + [SampleItemSnapshot.make()], [original[1]], Array(original.reversed())] {
      #expect(preview.cards(from: changed) == changed)
    }
  }

  @Test func onlyCompletePermutationsAreSentToTheAgent() async throws {
    let original = (0..<4).map { _ in SampleItemSnapshot.make() }
    let agent = TestSampleAgent(cards: original)
    let editor = SampleBoardViewModel(agent: agent)
    let observation = Task { await editor.observe() }
    defer { observation.cancel() }
    try await eventually { !editor.isLoading }
    let ids = original.map(\.id)
    for invalid in [Array(ids.dropLast()), [ids[0], ids[0], ids[2], ids[3]], [UUID()] + Array(ids.dropFirst()), ids] {
      await editor.reorder(ids: invalid, expectedArrangement: ids)
    }
    #expect(agent.commands.isEmpty && editor.cards == original)
    let finalArrangement = [ids[2], ids[0], ids[3], ids[1]]
    await editor.reorder(ids: finalArrangement, expectedArrangement: ids)
    #expect(agent.commands == [.reorder(finalArrangement)])
    #expect(editor.cards.map(\.id) == finalArrangement)
  }

  @Test func rejectedPreviewKeepsConfirmedArrangementAndReleasesTheCommandGate() async throws {
    let original = [SampleItemSnapshot.make(), SampleItemSnapshot.make()]
    let agent = TestSampleAgent(cards: original)
    agent.acceptsCommands = false
    let editor = SampleBoardViewModel(agent: agent)
    let observation = Task { await editor.observe() }
    defer { observation.cancel() }
    try await eventually { !editor.isLoading }
    await editor.reorder(ids: original.reversed().map(\.id), expectedArrangement: original.map(\.id))
    #expect(editor.cards == original)
    #expect(editor.errorMessage == SampleFailure.rejected.message)
    #expect(!editor.isPerformingCommand)
  }
}
