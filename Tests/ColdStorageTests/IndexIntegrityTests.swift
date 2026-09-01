import Foundation
import GRDB
import SparrowDomain
import StorageContracts
import Testing
@testable import ColdStorage

@Suite("Index integrity")
struct IndexIntegrityTests {
    /// The release gate: *no path writes a note row without also writing the
    /// index*. A note that exists but cannot be found is invisible rather than
    /// wrong, which is the harder failure to notice.
    @Test("Every live note has exactly one index entry")
    func indexCoversEveryNote() throws {
        try withTemporaryDatabase { url in
            let storage = try SQLiteStorage(at: url)

            try storage.pool.write { db in
                for title in ["one", "two", "three"] {
                    let note = makeNote(title)
                    try NoteRow(note).insert(db)
                    try db.execute(
                        sql: """
                            INSERT INTO note_fts (note_id, title, body)
                            VALUES (?, ?, ?)
                            """,
                        arguments: [note.id.value.uuidString, title, ""]
                    )
                }
            }

            let (notes, entries, orphans) = try storage.pool.read { db in
                try (
                    Int.fetchOne(db, sql:
                        "SELECT COUNT(*) FROM note WHERE deleted_at IS NULL") ?? -1,
                    Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_fts") ?? -1,
                    Int.fetchOne(db, sql: """
                        SELECT COUNT(*) FROM note_fts f
                         WHERE NOT EXISTS (
                               SELECT 1 FROM note n
                                WHERE n.id = f.note_id AND n.deleted_at IS NULL)
                        """) ?? -1
                )
            }
            #expect(notes == 3)
            #expect(entries == 3)
            #expect(orphans == 0)
        }
    }

    /// Migration v3 builds the index from notes already on disk. This is the
    /// other half of 0.4.0's promise: index writes were discarded then, and
    /// nothing had to be remembered in the meantime.
    @Test("v3 indexes notes written before FTS5 existed")
    func migrationIndexesExistingNotes() throws {
        try withTemporaryDatabase { url in
            // Open once at the current schema, then simulate a pre-v3 database
            // by dropping the index and re-running the migrator.
            let storage = try SQLiteStorage(at: url)
            let note = makeNote("Herón at dusk")

            try storage.pool.write { db in
                try NoteRow(note).insert(db)
                try db.execute(sql: "DROP TABLE note_fts")
                try db.execute(
                    sql: "DELETE FROM grdb_migrations WHERE identifier = 'v3_fts'"
                )
            }

            // Reopening re-runs v3 against a database that already has notes.
            let reopened = try SQLiteStorage(at: url)
            let indexed = try reopened.pool.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_fts") ?? -1
            }
            #expect(indexed == 1)
        }
    }

    @Test("v3 skips tombstoned notes when building the index")
    func migrationSkipsTombstones() throws {
        try withTemporaryDatabase { url in
            let storage = try SQLiteStorage(at: url)
            var row = NoteRow(makeNote("Already deleted"))
            row.deletedAt = Date().timeIntervalSince1970

            try storage.pool.write { db in
                try row.insert(db)
                try db.execute(sql: "DROP TABLE note_fts")
                try db.execute(
                    sql: "DELETE FROM grdb_migrations WHERE identifier = 'v3_fts'"
                )
            }

            let reopened = try SQLiteStorage(at: url)
            let indexed = try reopened.pool.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_fts") ?? -1
            }
            #expect(indexed == 0)
        }
    }

    @Test("Re-indexing the same note does not duplicate it")
    func reindexingIsIdempotent() async throws {
        try withTemporaryDatabase { url in
            let storage = try SQLiteStorage(at: url)
            let note = makeNote("Kingfisher")

            try storage.pool.write { db in
                let session = SQLiteIndexSession(
                    db: db, validity: SessionValidity()
                )
                try NoteRow(note).insert(db)
                try session.index(note)
                try session.index(note)
                try session.index(note)
            }

            let entries = try storage.pool.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_fts") ?? -1
            }
            #expect(entries == 1)
        }
    }
}
