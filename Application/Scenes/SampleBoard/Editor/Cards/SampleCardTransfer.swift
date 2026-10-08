import Foundation

/// Only identities cross the drag boundary; source fields remain live in the agent stream.
struct SampleCardTransfer: Codable, Sendable {
  let editorID: UUID
  let cardID: UUID
  let arrangement: [UUID]
}
