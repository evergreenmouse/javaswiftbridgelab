import Foundation

struct GridSlot: Hashable, Sendable {
  let row: Int
  let column: Int

  init(_ row: Int, _ column: Int) {
    self.row = row
    self.column = column
  }
}

struct GridDecoration: Equatable, Sendable {
  let slot: GridSlot
  let label: String

  init(slot: GridSlot, label: String) {
    self.slot = slot
    self.label = label
  }
}

enum LinkEndpoint: Hashable, Sendable {
  case position(Int)
  case decoration
}

struct GridLink: Hashable, Sendable {
  let from: LinkEndpoint
  let to: LinkEndpoint

  init(from: LinkEndpoint, to: LinkEndpoint) {
    self.from = from
    self.to = to
  }
}

/// Positions are ordered by insertion, not by row-major screen coordinates.
struct LayoutDefinition: Identifiable, Equatable, Sendable {
  let kind: SampleLayout
  var id: String { kind.rawValue }
  let title: String
  let rows: Int
  let columns: Int
  /// Slot sequence defines insertion/numbering sample, including the serpentine layout.
  let positions: [GridSlot]
  /// A separate top slot changes geometry only; its card remains movable and deletable.
  let separatesFirstCard: Bool
  let centersInitialAdd: Bool
  let decoration: GridDecoration?
  /// Logical connections are projected into fixed-size SF Symbol arrows by the UI.
  let links: [GridLink]

  var capacity: Int { positions.count + leadingCount }
  var leadingCount: Int { separatesFirstCard ? 1 : 0 }

  init(
    kind: SampleLayout, title: String, rows: Int = 3, columns: Int = 3,
    positions: [GridSlot], separatesFirstCard: Bool = false, centersInitialAdd: Bool = false,
    decoration: GridDecoration? = nil, links: [GridLink]
  ) {
    precondition(rows > 0 && columns > 0 && !positions.isEmpty)
    precondition(Set(positions).count == positions.count)
    precondition(
      positions.allSatisfy { (0..<rows).contains($0.row) && (0..<columns).contains($0.column) })
    if let decoration {
      precondition(!positions.contains(decoration.slot))
      precondition(
        (0..<rows).contains(decoration.slot.row) && (0..<columns).contains(decoration.slot.column))
    }
    for link in links {
      for endpoint in [link.from, link.to] {
        switch endpoint {
        case .position(let index): precondition(positions.indices.contains(index))
        case .decoration: precondition(decoration != nil)
        }
      }
    }
    self.kind = kind
    self.title = title
    self.rows = rows
    self.columns = columns
    self.positions = positions
    self.separatesFirstCard = separatesFirstCard
    self.centersInitialAdd = centersInitialAdd
    self.decoration = decoration
    self.links = links
  }
}

enum LayoutCatalog {
  private static let radialPositions: [GridSlot] = [
    GridSlot(1, 0), GridSlot(1, 2), GridSlot(0, 1), GridSlot(2, 1),
    GridSlot(0, 0), GridSlot(0, 2), GridSlot(2, 0), GridSlot(2, 2),
  ]

  private static let rowPositions: [GridSlot] = [
    GridSlot(0, 0), GridSlot(0, 1), GridSlot(0, 2),
    GridSlot(1, 0), GridSlot(1, 1), GridSlot(1, 2),
    GridSlot(2, 0), GridSlot(2, 1),
  ]

  private static func radialLinks(count: Int) -> [GridLink] {
    (0..<count).map { GridLink(from: .position($0), to: .decoration) }
  }

  static let stagedRadial = LayoutDefinition(
    kind: .stagedRadial, title: "Staged radial", positions: Array(radialPositions.prefix(7)),
    separatesFirstCard: true,
    decoration: GridDecoration(slot: GridSlot(1, 1), label: ""),
    links: radialLinks(count: 7)
  )

  static let sequence = LayoutDefinition(
    kind: .sequence, title: "Sequence",
    positions: [
      GridSlot(0, 0), GridSlot(0, 1), GridSlot(0, 2),
      GridSlot(1, 2), GridSlot(1, 1), GridSlot(1, 0),
      GridSlot(2, 0), GridSlot(2, 1),
    ],
    links: (0..<7).map { GridLink(from: .position($0), to: .position($0 + 1)) }
  )

  static let radial = LayoutDefinition(
    kind: .radial, title: "Radial", positions: radialPositions,
    decoration: GridDecoration(slot: GridSlot(1, 1), label: ""),
    links: radialLinks(count: 8)
  )

  static let matrix = LayoutDefinition(
    kind: .matrix, title: "Matrix", positions: rowPositions, links: []
  )

  static let stagedMatrix = LayoutDefinition(
    kind: .stagedMatrix, title: "Staged matrix", positions: Array(rowPositions.prefix(7)),
    separatesFirstCard: true, centersInitialAdd: true, links: []
  )

  static let all: [LayoutDefinition] = [stagedRadial, sequence, radial, matrix, stagedMatrix]

  /// UI geometry is chosen locally from a domain kind; the agent never receives this structure.
  static func definition(for kind: SampleLayout) -> LayoutDefinition {
    switch kind {
    case .radial: radial
    case .sequence: sequence
    case .stagedRadial: stagedRadial
    case .matrix: matrix
    case .stagedMatrix: stagedMatrix
    }
  }
}

/// The exact same projection controls cards, the add button, and visible arrows.
struct SampleGridProjection: Equatable, Sendable {
  let layout: LayoutDefinition
  let cardCount: Int

  init(layout: LayoutDefinition, cardCount: Int) {
    precondition((0...layout.capacity).contains(cardCount))
    self.layout = layout
    self.cardCount = cardCount
  }

  var gridCount: Int { max(0, cardCount - layout.leadingCount) }
  var addPosition: Int? { cardCount > 0 && cardCount < layout.capacity ? gridCount : nil }

  func positionIndex(forCardIndex index: Int) -> Int? {
    guard (layout.leadingCount..<cardCount).contains(index) else { return nil }
    return index - layout.leadingCount
  }

  func cardIndex(forPosition index: Int) -> Int? {
    guard (0..<gridCount).contains(index) else { return nil }
    return index + layout.leadingCount
  }

  /// Center the first add tile under a separate trigger card.
  func slot(forPosition index: Int) -> GridSlot {
    if layout.centersInitialAdd && gridCount == 0 && index == 0 {
      return GridSlot(0, layout.columns / 2)
    }
    return layout.positions[index]
  }

  /// Grid compacts unused logical rows without calculating their coordinates.
  var visibleRows: [Int] {
    let count = gridCount + (addPosition == nil ? 0 : 1)
    var rows = Set((0..<count).map { slot(forPosition: $0).row })
    if let decoration = layout.decoration { rows.insert(decoration.slot.row) }
    return rows.sorted()
  }

  /// Include the next add slot, but omit every future unoccupied slot.
  func visibleLinks(showAdd: Bool = true) -> [GridLink] {
    func isVisible(_ endpoint: LinkEndpoint) -> Bool {
      switch endpoint {
      case .decoration: return layout.decoration != nil
      case .position(let index):
        return index < gridCount || (showAdd && index == addPosition)
      }
    }
    return layout.links.filter { isVisible($0.from) && isVisible($0.to) }
  }
}
