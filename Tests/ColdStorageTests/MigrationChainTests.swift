import Foundation
import GRDB
import SparrowDomain
import StorageContracts
import Testing
@testable import ColdStorage

/// Every migration, run against a database that predates it.
///
/// ⚠️ **The per-migration tests are not this test.** Each of those opens a
/// current database and checks one step. This one builds a database at an
/// *older* schema, puts data in it, and runs the chain forward — which is what
/// actually happens on a device that skipped a release.
///
/// A migration is only correct against the data that was there before it.
@Suite("Migration chain")
struct MigrationChainTests {
    /// Applies migrations up to and including `identifier`, and no further.
    private func database(
        at url: URL,
        upTo identifier: String
    ) throws -> DatabasePool {
        // `SQLiteStorage` creates this; opening a pool directly does not.
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let pool = try DatabasePool(path: url.path, configuration: configuration)
        try Migrations.migrator().migrate(pool, upTo: identifier)
        return pool
    }

    private static let noon = Date(timeIntervalSince1970: 1_756_814_400)

    /// ⚠️ Historical rows are written with **raw SQL**, not `NoteRow`.
    ///
    /// A record type describes the schema as it is *today* — `NoteRow` carries
    /// `day`, which does not exist before v5, so inserting one into a v2
    /// database fails with *"table note has no column named day"*. Writing the
    /// columns that existed at the time is the only honest way to build an old
    /// database.
    private func insertNoteAtV2(
        _ note: Note,
        into db: Database
    ) throws {
        try db.execute(sql: """
            INSERT INTO note
                (id, notebook_id, kind, title_data, title_plain,
                 body_data, body_plain, is_pinned, observed_at,
                 created_at, updated_at, local_version)
            VALUES (?, ?, ?, NULL, ?, NULL, ?, 0, ?, ?, ?, 0)
            """, arguments: [
                note.id.value.uuidString,
                note.notebookID.value.uuidString,
                note.kind.rawValue,
                note.plainTitle,
                note.plainBody,
                note.observedAt?.timeIntervalSince1970,
                note.createdAt.timeIntervalSince1970,
                note.updatedAt.timeIntervalSince1970,
            ])
    }

    @Test("Every migration applies in order, from empty")
    func theWholeChainApplies() throws {
        try withTemporaryDatabase { url in
            let applied = try SQLiteStorage(at: url).pool.read { db in
                try String.fetchAll(
                    db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid"
                )
            }
            #expect(applied == [
                "v1_initial", "v2_note", "v3_fts", "v4_tags",
                "v5_daily_unique", "v6_daily_day_from_observed",
            ])
        }
    }

    /// v1 → v5, carrying a notebook the whole way.
    @Test("A notebook written at v1 survives every later migration")
    func notebookSurvivesTheChain() throws {
        try withTemporaryDatabase { url in
            // The notebook table has not changed since v1, so its record type
            // still describes it — unlike `NoteRow`.
            let notebook = makeNotebook("Wetlands")
            let pool = try database(at: url, upTo: "v1_initial")
            try pool.write { try NotebookRow(notebook).insert($0) }
            try pool.close()

            // Everything from v2 onward now runs against real data.
            let upgraded = try SQLiteStorage(at: url)
            let found = try upgraded.pool.read { db in
                try NotebookRow.fetchOne(db, key: notebook.id.value.uuidString)
            }
            #expect(try found?.toDomain().name == "Wetlands")
        }
    }

    /// v2 → v5. This is the one that matters: v3 builds the FTS index from
    /// existing notes and v5 backfills their `day` column, so a note written
    /// before either has to come out the other side searchable and dated.
    @Test("A note written at v2 is indexed by v3 and dated by v5")
    func noteWrittenAtV2IsUpgraded() throws {
        try withTemporaryDatabase { url in
            var note = makeNote("Herón at dusk", kind: .daily)
            note.observedAt = Self.noon

            let pool = try database(at: url, upTo: "v2_note")
            try pool.write { try insertNoteAtV2(note, into: $0) }
            // v2 has neither an FTS table nor a `day` column.
            let before = try pool.read { db in
                (try db.tableExists("note_fts"), try db.columns(in: "note").map(\.name))
            }
            #expect(!before.0)
            #expect(!before.1.contains("day"))
            try pool.close()

            let upgraded = try SQLiteStorage(at: url)
            let (indexed, day) = try upgraded.pool.read { db in
                try (
                    Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_fts") ?? -1,
                    String.fetchOne(db, sql: "SELECT day FROM note LIMIT 1")
                )
            }

            // v3 indexed it…
            #expect(indexed == 1)
            // …and v6 corrected the day to the one it was observed on.
            #expect(day == DayKey.string(for: Self.noon))

            // Which means it is findable, diacritics folded, through the
            // ordinary read path.
            let hits = try upgraded.pool.read { db in
                try String.fetchAll(db, sql: """
                    SELECT note_id FROM note_fts WHERE note_fts MATCH ?
                    """, arguments: ["\"heron\"*"])
            }
            #expect(hits == [note.id.value.uuidString])
        }
    }

    /// v4 → v5, with a tagged note. The join must survive the last migration.
    @Test("Tags written at v4 survive v5")
    func tagsSurviveV5() throws {
        try withTemporaryDatabase { url in
            let tag = makeTag("Wetlands")
            var note = makeNote("Tagged")
            note.tagIDs = [tag.id]

            let pool = try database(at: url, upTo: "v4_tags")
            try pool.write { db in
                try TagRow(tag, at: Self.noon).insert(db)
                // Still pre-v5, so still raw SQL.
                try insertNoteAtV2(note, into: db)
                try NoteTags.write(note.tagIDs, for: note.id, in: db)
            }
            try pool.close()

            let upgraded = try SQLiteStorage(at: url)
            let tags = try upgraded.pool.read { db in
                try NoteTags.read(note.id, from: db)
            }
            #expect(tags == [tag.id])
        }
    }

    /// A shipped migration is never edited, so re-opening must be a no-op
    /// however many times it happens.
    @Test("Re-opening a fully migrated database changes nothing")
    func reopeningIsIdempotent() throws {
        try withTemporaryDatabase { url in
            _ = try SQLiteStorage(at: url)
            let first = try SQLiteStorage(at: url).pool.read { db in
                try (
                    NotebookRow.fetchCount(db),
                    String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
                )
            }
            let second = try SQLiteStorage(at: url).pool.read { db in
                try (
                    NotebookRow.fetchCount(db),
                    String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
                )
            }
            #expect(first.0 == second.0)
            #expect(first.1 == second.1)
        }
    }
}
