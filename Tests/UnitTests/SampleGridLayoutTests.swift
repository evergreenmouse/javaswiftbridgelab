import Foundation
import Testing

@testable import JavaSwiftBridgeLab

@MainActor
struct SampleGridLayoutTests {
  @Test func configurationMatchesAgreedArrangementAndCapacity() {
    #expect(LayoutCatalog.all.count == 5)
    #expect(LayoutCatalog.all.allSatisfy { $0.capacity == 8 })
    #expect(
      LayoutCatalog.radial.positions == [
        GridSlot(1, 0), GridSlot(1, 2), GridSlot(0, 1), GridSlot(2, 1),
        GridSlot(0, 0), GridSlot(0, 2), GridSlot(2, 0), GridSlot(2, 2),
      ])
    #expect(
      LayoutCatalog.sequence.positions == [
        GridSlot(0, 0), GridSlot(0, 1), GridSlot(0, 2), GridSlot(1, 2),
        GridSlot(1, 1), GridSlot(1, 0), GridSlot(2, 0), GridSlot(2, 1),
      ])
    #expect(LayoutCatalog.stagedRadial.positions == Array(LayoutCatalog.radial.positions.prefix(7)))
    #expect(LayoutCatalog.stagedRadial.separatesFirstCard)
    #expect(
      LayoutCatalog.matrix.positions == [
        GridSlot(0, 0), GridSlot(0, 1), GridSlot(0, 2), GridSlot(1, 0),
        GridSlot(1, 1), GridSlot(1, 2), GridSlot(2, 0), GridSlot(2, 1),
      ])
    #expect(LayoutCatalog.stagedMatrix.positions == Array(LayoutCatalog.matrix.positions.prefix(7)))
    #expect(LayoutCatalog.stagedMatrix.centersInitialAdd)
    #expect(LayoutCatalog.matrix.links.isEmpty && LayoutCatalog.stagedMatrix.links.isEmpty)
  }

  @Test func projectionIsContiguousForEverySupportedCount() {
    for layout in LayoutCatalog.all {
      for count in 1...8 {
        let projection = SampleGridProjection(layout: layout, cardCount: count)
        #expect(projection.gridCount == count - layout.leadingCount)
        #expect(projection.addPosition == (count == 8 ? nil : count - layout.leadingCount))
        for index in 0..<count {
          if index < layout.leadingCount {
            #expect(projection.positionIndex(forCardIndex: index) == nil)
          } else {
            let position = projection.positionIndex(forCardIndex: index)
            #expect(position == index - layout.leadingCount)
            #expect(projection.cardIndex(forPosition: position!) == index)
          }
        }
        #expect(projection.cardIndex(forPosition: projection.gridCount) == nil)
      }
    }
  }

  @Test func arrowsIncludePlusAndNeverPointToFutureEmptyPositions() {
    for count in 1...8 {
      let a = SampleGridProjection(layout: LayoutCatalog.radial, cardCount: count)
      let b = SampleGridProjection(layout: LayoutCatalog.sequence, cardCount: count)
      let c = SampleGridProjection(layout: LayoutCatalog.stagedRadial, cardCount: count)
      #expect(a.visibleLinks().count == min(count + 1, 8))
      #expect(b.visibleLinks().count == min(count, 7))
      #expect(c.visibleLinks().count == min(count, 7))
      #expect(a.visibleLinks(showAdd: false).count == count)
      #expect(b.visibleLinks(showAdd: false).count == count - 1)
      #expect(c.visibleLinks(showAdd: false).count == count - 1)
    }
  }

}
