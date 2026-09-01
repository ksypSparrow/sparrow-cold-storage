import Foundation
import GRDB
import SparrowDomain
import StorageContracts

/// Note reads and writes inside a transaction.
struct SQLiteNoteSession: NoteSessionAccess {
    let db: Database
    let validity: SessionValidity
    let touched: TouchedIdentifiers

    func note(_ id: NoteID) throws -> Note? {
        try validity.check()
        return try NoteRow.live()
            .filter(Column("id") == id.value.uuidString)
            .fetchOne(db)?
            .toDomain()
    }

    func insert(_ note: Note) throws {
        try validity.check()
        guard try row(note.id) == nil else {
            throw StorageError.constraintViolated(
                "a note with id \(note.id) already exists"
            )
        }
        try NoteRow(note).insert(db)
        touched.note(note.id)
    }

    func update(_ note: Note) throws {
        try validity.check()
        guard let existing = try row(note.id), existing.deletedAt == nil else {
            throw StorageError.notFound
        }

        var updated = NoteRow(note)
        // Carry the sync seam forward; it is storage's, not the domain's.
        updated.ownerID = existing.ownerID
        updated.remoteVersion = existing.remoteVersion
        updated.lastEditor = existing.lastEditor
        updated.localVersion = existing.localVersion + 1
        try updated.update(db)
        touched.note(note.id)
    }

    func markDeleted(_ id: NoteID, at date: Date) throws {
        try validity.check()
        guard let existing = try row(id), existing.deletedAt == nil else {
            throw StorageError.notFound
        }
        try db.execute(
            sql: """
                UPDATE note
                   SET deleted_at = ?, local_version = local_version + 1
                 WHERE id = ?
                """,
            arguments: [date.timeIntervalSince1970, id.value.uuidString]
        )
        touched.note(id)
    }

    private func row(_ id: NoteID) throws -> NoteRow? {
        try NoteRow.filter(Column("id") == id.value.uuidString).fetchOne(db)
    }
}

/// Accepts index writes and discards them, until FTS5 arrives in 0.5.0.
///
/// Dropping them loses nothing: the text lives in the `note` table, and 0.5.0's
/// migration builds the index from there. Refusing them instead would block
/// every note write, since a save indexes in the same transaction.
///
/// ⚠️ Reading is a different matter — see `UnavailableSearchIndex`. Accepting a
/// write you discard is harmless here; answering a search from an index that
/// does not exist would be a lie.
struct DiscardingIndexSession: SearchIndexWriting {
    let validity: SessionValidity

    func index(_ note: Note) throws { try validity.check() }
    func remove(_ id: NoteID) throws { try validity.check() }
}

/// Refuses to answer searches until there is an index to answer from.
struct UnavailableSearchIndex: SearchIndexing {
    func matches(_ text: String, limit: Int) async throws -> [NoteID] {
        throw StorageError.unavailable(
            "full-text search arrives with FTS5, in 0.5.0"
        )
    }

    func rebuild() async throws {
        throw StorageError.unavailable(
            "full-text search arrives with FTS5, in 0.5.0"
        )
    }
}
