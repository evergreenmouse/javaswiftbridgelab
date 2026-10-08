import Foundation
import Observation

/// Read-only observable presentation contract consumed by generic SwiftUI views.
@MainActor
protocol SampleBoardState: AnyObject, Observable {
  var cards: [SampleItemSnapshot] { get }
  var layout: LayoutDefinition { get }
  var isLoading: Bool { get }
  var errorMessage: String? { get }
  var canInteract: Bool { get }
  var canAdd: Bool { get }
  var isPerformingCommand: Bool { get }
  func canDelete(id: UUID) -> Bool
}

extension SampleBoardState {
  var projection: SampleGridProjection {
    SampleGridProjection(layout: layout, cardCount: cards.count)
  }
  func cardIndex(id: UUID) -> Int? { cards.firstIndex { $0.id == id } }
  func number(id: UUID) -> Int? { cardIndex(id: id).map { $0 + 1 } }
}

/// UI intentions; failures are exposed through errorMessage rather than silently discarded.
@MainActor
protocol SampleBoardActions: AnyObject {
  func observe() async
  func select(_ layout: LayoutDefinition) async
  func appendCopy() async -> UUID?
  func delete(id: UUID) async
  func update(original: SampleItemSnapshot, draft: SampleItemDraft) async -> Bool
  func reorder(ids: [UUID], expectedArrangement: [UUID]) async
  func move(id: UUID, to destination: UUID, expectedArrangement: [UUID]) async
  func move(id: UUID, by offset: Int) async
}
