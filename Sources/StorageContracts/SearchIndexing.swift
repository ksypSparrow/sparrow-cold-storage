import Foundation
import SparrowDomain

/// Searching the index, from outside a transaction.
///
/// Backed by a naive substring scan until 0.5.0 replaces it with SQLite FTS5.
/// The protocol does not change between the two.
public protocol SearchIndexing: Sendable {
    func matches(_ text: String, limit: Int) async throws -> [NoteID]

    /// Discards and rebuilds the whole index. Used after a bulk import or a
    /// migration that changes tokenisation.
    func rebuild() async throws
}

/// Maintaining the index inside a transaction, so a note and its index entry
/// are written together or not at all.
public protocol SearchIndexWriting {
    func index(_ note: Note) throws
    func remove(_ id: NoteID) throws
}
