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
