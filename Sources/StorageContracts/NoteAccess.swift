import Foundation
import SparrowDomain

/// Reading notes from outside a transaction. Asynchronous, because it has to
/// reach the database.
public protocol NoteReading: Sendable {
    func note(_ id: NoteID) async throws -> Note?
    func notes(_ ids: [NoteID]) async throws -> [Note]
    func recentNotes(limit: Int) async throws -> [Note]

    /// The Find query: structural fields, optional free text, and an order.
    func notes(
        matching filter: NoteFilter,
        sort: NoteSort,
        limit: Int
    ) async throws -> [Note]

    func count(matching filter: NoteFilter) async throws -> Int
}

public extension NoteReading {
    /// Every live note. `count(matching: .all)`, named for the common case.
    func count() async throws -> Int {
        try await count(matching: .all)
    }
}

/// Reading and writing notes **inside** a transaction.
///
/// Synchronous, and that is the whole point — see `StorageSession`. Reads are
/// here too so that a write can see its own effects before it commits.
public protocol NoteSessionAccess {
    func note(_ id: NoteID) throws -> Note?

    func insert(_ note: Note) throws
    func update(_ note: Note) throws

    /// Records a tombstone. There is deliberately no `delete`.
    ///
    /// Removing a row destroys the tombstone, and without a tombstone a
    /// deleted note reappears from another device the first time V2 syncs.
    func markDeleted(_ id: NoteID, at date: Date) throws
}
