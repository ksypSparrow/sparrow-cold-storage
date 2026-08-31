import Foundation
import SparrowDomain

public protocol StorageObserving: Sendable {
    /// Emits after a write transaction commits. Never mid-transaction.
    ///
    /// Each access returns an independent stream; several consumers can observe
    /// at once.
    var changes: AsyncStream<StoredChange> { get }
}

/// What changed — **identifiers, not values**.
///
/// A consumer that wants the note fetches it, so it can never act on a payload
/// that was already stale when it arrived.
public enum StoredChange: Hashable, Sendable {
    case notes([NoteID])
    case notebooks([NotebookID])
    /// Bulk import, migration, restore. Assume everything changed.
    case reloaded
}
