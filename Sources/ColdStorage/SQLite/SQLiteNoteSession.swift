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
        guard let row = try NoteRow.live()
            .filter(Column("id") == id.value.uuidString)
            .fetchOne(db)
        else { return nil }
        return try row.toDomain(tagIDs: NoteTags.read(id, from: db))
    }

    func insert(_ note: Note) throws {
        try validity.check()
        guard try row(note.id) == nil else {
            throw StorageError.constraintViolated(
                "a note with id \(note.id) already exists"
            )
        }
        try NoteRow(note).insert(db)
        try NoteTags.write(note.tagIDs, for: note.id, in: db)
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
        try NoteTags.write(note.tagIDs, for: note.id, in: db)
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
        // ⚠️ The `note_tag` rows stay. A soft-deleted note keeps its tags, so
        // undeleting restores them — and V2 merging a delete-here/edit-there
        // does not have to reconstruct the association.
        touched.note(id)
    }

    private func row(_ id: NoteID) throws -> NoteRow? {
        try NoteRow.filter(Column("id") == id.value.uuidString).fetchOne(db)
    }
}


/// The `note_tag` join, in one place.
///
/// Tag order is user-visible, so `position` is written on the way in and
/// ordered by on the way out. A plain join returns rows in whatever order
/// SQLite finds convenient, and a note whose tags reshuffle between reads
/// looks like a bug in the view that drew it.
enum NoteTags {
    static func read(_ id: NoteID, from db: Database) throws -> [TagID] {
        try String.fetchAll(db, sql: """
            SELECT nt.tag_id
              FROM note_tag nt
              JOIN tag t ON t.id = nt.tag_id
             WHERE nt.note_id = ? AND t.deleted_at IS NULL
             ORDER BY nt.position
            """, arguments: [id.value.uuidString])
            .compactMap(TagID.init(slug:))
    }

    /// Replaces the whole set, matching `NoteEdit.tagIDs`' semantics.
    static func write(
        _ tagIDs: [TagID],
        for id: NoteID,
        in db: Database
    ) throws {
        try db.execute(
            sql: "DELETE FROM note_tag WHERE note_id = ?",
            arguments: [id.value.uuidString]
        )
        // Deduplicated on the way in: the domain keeps `tagIDs` an array for
        // order, and the join's primary key would reject a repeat anyway.
        var seen: Set<TagID> = []
        for (position, tagID) in tagIDs.enumerated()
        where seen.insert(tagID).inserted {
            try db.execute(
                sql: """
                    INSERT INTO note_tag (note_id, tag_id, position)
                    VALUES (?, ?, ?)
                    """,
                arguments: [id.value.uuidString, tagID.slug, position]
            )
        }
    }

    /// Every note's tags, in one query. Reading them per note would be an
    /// N+1 on the busiest path in the app.
    static func read(
        _ ids: [NoteID],
        from db: Database
    ) throws -> [NoteID: [TagID]] {
        guard !ids.isEmpty else { return [:] }
        let strings = ids.map(\.value.uuidString)
        let placeholders = Array(repeating: "?", count: strings.count)
            .joined(separator: ", ")

        var result: [NoteID: [TagID]] = [:]
        let rows = try Row.fetchAll(db, sql: """
            SELECT nt.note_id, nt.tag_id
              FROM note_tag nt
              JOIN tag t ON t.id = nt.tag_id
             WHERE nt.note_id IN (\(placeholders)) AND t.deleted_at IS NULL
             ORDER BY nt.note_id, nt.position
            """, arguments: StatementArguments(strings))

        for row in rows {
            guard let noteUUID = UUID(uuidString: row["note_id"]),
                  let tagID = TagID(slug: row["tag_id"])
            else { continue }
            result[NoteID(noteUUID), default: []].append(tagID)
        }
        return result
    }
}
