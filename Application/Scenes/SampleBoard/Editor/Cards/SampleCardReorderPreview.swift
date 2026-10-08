import Foundation

/// Visual ID sequence only: metrics and all other fields continue to come from the live snapshot.
struct SampleCardReorderPreview {
  let id = UUID()
  let payload: SampleCardTransfer
  private(set) var arrangement: [UUID]

  init(payload: SampleCardTransfer) {
    self.payload = payload
    arrangement = payload.arrangement
  }

  mutating func move(to destination: Int) {
    guard let source = arrangement.firstIndex(of: payload.cardID),
      arrangement.indices.contains(destination), source != destination else { return }
    arrangement.insert(arrangement.remove(at: source), at: destination)
  }

  func cards(from latest: [SampleItemSnapshot]) -> [SampleItemSnapshot] {
    guard latest.map(\.id) == payload.arrangement else { return latest }
    let byID = Dictionary(uniqueKeysWithValues: latest.map { ($0.id, $0) })
    return arrangement.compactMap { byID[$0] }
  }
}
