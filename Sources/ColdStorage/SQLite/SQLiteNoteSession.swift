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
