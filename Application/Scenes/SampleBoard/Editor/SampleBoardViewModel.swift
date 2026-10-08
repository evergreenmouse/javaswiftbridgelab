import Foundation
import Observation

/// The editor's observable model: latest source values and serial commands.
@MainActor @Observable
final class SampleBoardViewModel<Agent: SampleAgentContract>:
    SampleBoardActions,
    SampleBoardState
{
    /// The sole copy of sample fields; even a valid empty snapshot is authoritative.
    private var snapshot: SampleSnapshot?
    /// Source/SDK-confirmed IDs; an accepted command can precede its corresponding stream update.
    private var confirmedArrangement: [UUID] = []
    private(set) var layout: LayoutDefinition = LayoutCatalog.radial
    private var commandFailure: SampleFailure?
    /// Keep the command gate across suspension.
    private(set) var isPerformingCommand = false
    private let agent: Agent
    private var isObserving = false
    
    init(agent: Agent) {
        self.agent = agent
    }
    
    /// Apply confirmed positions to current fields; a drag payload never freezes metrics.
    var cards: [SampleItemSnapshot] {
        guard let snapshot, snapshot.issue == nil else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })
        return confirmedArrangement.compactMap { byID[$0] }
    }
    /// An up-to-date empty snapshot shows an empty state rather than an endless loading indicator.
    var isLoading: Bool {
        snapshot == nil || (snapshot?.isUpToDate == false && cards.isEmpty && snapshot?.issue == nil)
    }
    private var isActive: Bool { snapshot?.isActive == true }
    private var isUpToDate: Bool { snapshot?.isUpToDate == true }
    var canInteract: Bool { isActive && isUpToDate && snapshot?.issue == nil }
    var canAdd: Bool {
        canInteract && !isPerformingCommand && !cards.isEmpty
        && cards.count < layout.capacity && cards.last?.isLoading == false
    }
    var errorMessage: String? {
        if let issue = snapshot?.issue { return issue.message }
        if let commandFailure { return commandFailure.message }
        if let validation = snapshot?.validationError, !validation.isEmpty { return validation }
        return nil
    }
    func canDelete(id: UUID) -> Bool {
        canInteract && !isPerformingCommand
        && cards.count > 1 && confirmedArrangement.contains(id)
    }
    
    /// The view's structured task owns observation; cancellation detaches the legacy listeners.
    func observe() async {
        guard !isObserving else { return }
        isObserving = true
        defer { isObserving = false }
        for await snapshot in await agent.updates() {
            guard !Task.isCancelled else { break }
            apply(snapshot)
        }
        await agent.finish()
    }
    
    /// Stream updates remain authoritative, including structural changes during a native drag.
    private func apply(_ incoming: SampleSnapshot) {
        snapshot = incoming
        confirmedArrangement = incoming.issue == nil ? incoming.items.map(\.id) : []
        layout = incoming.kind.map(LayoutCatalog.definition(for:)) ?? layout
    }

    /// One serial command gate and failure-mapping path serve every source action.
    private func perform<Value: Sendable>(_ operation: () async -> Result<Value, SampleFailure>) async
    -> Value?
    {
        guard canInteract, !isPerformingCommand else { return nil }
        isPerformingCommand = true
        commandFailure = nil
        defer { isPerformingCommand = false }
        switch await operation() {
        case .success(let value): return value
        case .failure(let failure):
            commandFailure = failure
            return nil
        }
    }
    
    func select(_ layout: LayoutDefinition) async {
        _ = await perform { await agent.selectKind(layout.kind) }
    }
    
    func appendCopy() async -> UUID? {
        guard canAdd else { return nil }
        return await perform { await agent.appendCopy() }
    }
    
    func delete(id: UUID) async {
        guard canDelete(id: id) else { return }
        _ = await perform { await agent.delete(id: id) }
    }
    
    /// Dismiss the item editor only on success; send a patch to preserve newer live metrics.
    func update(original: SampleItemSnapshot, draft: SampleItemDraft) async -> Bool {
        return await perform {
            await agent.update(id: original.id, changes: draft.changes(from: original))
        } != nil
    }
    
    /// A drop is one command. Reject a payload made before a structural source change.
    func move(id: UUID, to destination: UUID, expectedArrangement: [UUID]) async {
        guard canInteract, !isPerformingCommand else { return }
        guard confirmedArrangement == expectedArrangement else {
            commandFailure = .conflict
            return
        }
        guard let source = cardIndex(id: id), let target = cardIndex(id: destination),
              source != target, cards[source].isLoading == false else { return }
        var arrangement = expectedArrangement
        arrangement.insert(arrangement.remove(at: source), at: target)
        await reorder(ids: arrangement, expectedArrangement: expectedArrangement)
    }

    /// Confirm the visual ID sequence atomically against the source; never send copied fields.
    func reorder(ids: [UUID], expectedArrangement: [UUID]) async {
        guard canInteract, !isPerformingCommand else { return }
        guard confirmedArrangement == expectedArrangement else {
            commandFailure = .conflict
            return
        }
        guard ids.count == expectedArrangement.count, Set(ids) == Set(expectedArrangement),
              Set(ids).count == ids.count, ids != expectedArrangement else { return }
        let accepted = await perform {
            await agent.reorder(ids: ids, expectedArrangement: expectedArrangement)
        } != nil
        if accepted && confirmedArrangement == expectedArrangement { confirmedArrangement = ids }
    }

    /// VoiceOver and pointer drops use the same insertion command.
    func move(id: UUID, by offset: Int) async {
        guard let source = cardIndex(id: id), cards.indices.contains(source + offset) else { return }
        await move(id: id, to: cards[source + offset].id, expectedArrangement: confirmedArrangement)
    }
}
