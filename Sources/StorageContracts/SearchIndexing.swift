import Foundation
import SparrowDomain

/// The full-text index over note content.
///
/// Backed by a naive substring scan in 0.1.0 and by SQLite FTS5 from 0.5.0. The
/// protocol does not change between the two.
public protocol SearchIndexing: Sendable {
    func index(_ note: Note) async throws
    func remove(_ id: NoteID) async throws
    func matches(_ text: String, limit: Int) async throws -> [NoteID]

    /// Discards and rebuilds the whole index. Used after a bulk import or a
    /// migration that changes tokenisation.
    func rebuild() async throws
}
