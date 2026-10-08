import Foundation

/// Capability contract for observing and editing a complex sample.
/// Only Swift Sendable values cross this application port; no raw SDK types are exposed.
protocol SampleAgentContract: Sendable {
  /// One consumer per one-shot agent; later subscriptions finish immediately.
  /// Cancellation or finish removes its listener; another scene creates a fresh agent.
  func updates() async -> AsyncStream<SampleSnapshot>
  func finish() async
  func appendCopy() async -> Result<UUID, SampleFailure>
  func delete(id: UUID) async -> Result<Void, SampleFailure>
  func update(id: UUID, changes: SampleItemChanges) async -> Result<Void, SampleFailure>
  /// Reject a sample based on obsolete source positions instead of overwriting external edits.
  func reorder(ids: [UUID], expectedArrangement: [UUID]) async -> Result<Void, SampleFailure>
  func selectKind(_ kind: SampleLayout) async -> Result<Void, SampleFailure>
}
