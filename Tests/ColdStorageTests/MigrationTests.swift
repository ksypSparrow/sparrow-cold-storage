import Foundation
import GRDB
import SparrowDomain
import StorageContracts
import Testing
@testable import ColdStorage

@Suite("Migrations")
struct MigrationTests {
    @Test("v1 runs on an empty file and seeds a notebook")
    func migrationRunsOnAnEmptyFile() async throws {
        try withTemporaryDatabase { url in
            #expect(!FileManager.default.fileExists(atPath: url.path))
            let storage = try SQLiteStorage(at: url)

            let seeded = try storage.pool.read { db in
                try NotebookRow.fetchCount(db)
            }
            #expect(seeded == 1)
        }
    }

    @Test("Opening the same database twice is safe")
    func migrationIsIdempotent() throws {
        try withTemporaryDatabase { url in
            let first = try SQLiteStorage(at: url)
            let afterFirst = try first.pool.read { try NotebookRow.fetchCount($0) }

            // A second open re-runs the migrator, which must recognise that v1
            // has already been applied — and must not seed a second notebook.
            let second = try SQLiteStorage(at: url)
            let afterSecond = try second.pool.read { try NotebookRow.fetchCount($0) }

            #expect(afterFirst == 1)
            #expect(afterSecond == 1)
        }
    }

    /// Nothing writes to the journal until 0.3.0. It is created now because
    /// adding a table to a shipped schema is a migration, and adding it here
    /// is three lines.
    @Test("v1 creates the journal table, empty and ahead of its first writer")
    func journalTableExistsFromV1() throws {
        try withTemporaryDatabase { url in
            let storage = try SQLiteStorage(at: url)

            let (exists, rows) = try storage.pool.read { db in
                try (
                    db.tableExists("journal"),
                    Int.fetchOne(db, sql: "SELECT COUNT(*) FROM journal") ?? -1
                )
            }
            #expect(exists)
            #expect(rows == 0)
        }
    }

    @Test("Every V2 seam column is present on notebook from v1")
    func syncSeamColumnsExistFromV1() throws {
        try withTemporaryDatabase { url in
            let storage = try SQLiteStorage(at: url)

            let columns = try storage.pool.read { db in
                try db.columns(in: "notebook").map(\.name)
            }
            for seam in [
                "owner_id", "local_version", "remote_version",
                "deleted_at", "last_editor",
            ] {
                #expect(columns.contains(seam), "notebook is missing \(seam)")
            }
        }
    }

    @Test("Foreign keys are enforced, so parent_id cannot dangle")
    func foreignKeysAreOn() throws {
        try withTemporaryDatabase { url in
            let storage = try SQLiteStorage(at: url)

            let enabled = try storage.pool.read { db in
                try Bool.fetchOne(db, sql: "PRAGMA foreign_keys") ?? false
            }
            #expect(enabled)
        }
    }

    @Test("v2 creates the note table with both rich-text column pairs")
    func noteTableExistsFromV2() throws {
        try withTemporaryDatabase { url in
            let storage = try SQLiteStorage(at: url)

            let columns = try storage.pool.read { db in
                try db.columns(in: "note").map(\.name)
            }
            for column in [
                "title_data", "title_plain", "body_data", "body_plain",
                "notebook_id", "kind", "is_pinned", "observed_at",
                "owner_id", "local_version", "remote_version",
                "deleted_at", "last_editor",
            ] {
                #expect(columns.contains(column), "note is missing \(column)")
            }
        }
    }

    @Test("Both list orderings are indexed")
    func listOrderingsAreIndexed() throws {
        try withTemporaryDatabase { url in
            let storage = try SQLiteStorage(at: url)

            let indexes = try storage.pool.read { db in
                try db.indexes(on: "note").map(\.name)
            }
            #expect(indexes.contains("note_on_notebook_updated"))
            #expect(indexes.contains("note_on_kind_updated"))
        }
    }

    /// The first place SQLite itself enforces integrity rather than our own
    /// checks doing it. A note whose notebook does not exist is unreachable
    /// from the sidebar, and would be invisible rather than wrong.
    @Test("A note cannot reference a notebook that does not exist")
    func noteRequiresARealNotebook() throws {
        try withTemporaryDatabase { url in
            let storage = try SQLiteStorage(at: url)
            let orphan = makeNote("Orphan", in: NotebookID())

            #expect(throws: (any Error).self) {
                try storage.pool.write { db in try NoteRow(orphan).insert(db) }
            }
        }
    }

    /// `onDelete: .restrict`. A notebook row is never actually removed — the
    /// service tombstones it — but if one ever were, its notes must not be
    /// silently orphaned or silently destroyed.
    @Test("A notebook with notes cannot be hard-deleted")
    func notebookWithNotesIsProtected() throws {
        try withTemporaryDatabase { url in
            let storage = try SQLiteStorage(at: url)
            try storage.pool.write { db in
                try NoteRow(makeNote("Attached")).insert(db)
            }

            #expect(throws: (any Error).self) {
                try storage.pool.write { db in
                    try db.execute(
                        sql: "DELETE FROM notebook WHERE id = ?",
                        arguments: [DefaultNotebook.identifier.value.uuidString]
                    )
                }
            }
        }
    }

    @Test("Data written before a reopen is still there")
    func dataSurvivesAReopen() async throws {
        try withTemporaryDatabase { url in
            _ = try SQLiteStorage(at: url)
            let reopened = try SQLiteStorage(at: url)

            let names = try reopened.pool.read { db in
                try NotebookRow.fetchAll(db).map(\.name)
            }
            #expect(names == [DefaultNotebook.name])
        }
    }
}
