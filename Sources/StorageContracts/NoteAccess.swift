import Foundation
import SparrowDomain

/// Reading notes. Available everywhere, inside a transaction and outside one.
public protocol NoteReading: Sendable {
    func note(_ id: NoteID) async throws -> Note?
    func notes(_ ids: [NoteID]) async throws -> [Note]
    func recentNotes(limit: Int) async throws -> [Note]
    func count() async throws -> Int
}

/// Writing notes. **Obtainable only from inside a `write { }` body** — see
/// `StorageSession`. That is what makes "saved but not indexed" unwritable.
public protocol NoteWriting: Sendable {
    func insert(_ note: Note) async throws
    func update(_ note: Note) async throws

    /// Records a tombstone. There is deliberately no `delete`.
    ///
    /// Removing a row destroys the tombstone, and without a tombstone a deleted
    /// note reappears from another device the first time V2 syncs. Making the
    /// destructive verb unavailable is cheaper than remembering not to use it.
    func markDeleted(_ id: NoteID, at: Date) async throws
}
