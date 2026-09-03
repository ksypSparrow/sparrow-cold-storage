import Foundation
import GRDB

/// The schema, one append-only step at a time.
///
/// ⚠️ **A shipped migration is never edited.** Changing `v1` after it has run
/// on a real device leaves that device on a schema no code describes any more.
/// Every change is a new migration, forever.
enum Migrations {
    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try createNotebookTable(db)
            try createJournalTable(db)
            try seedDefaultNotebook(db)
        }

        migrator.registerMigration("v2_note") { db in
            try createNoteTable(db)
        }

        migrator.registerMigration("v3_fts") { db in
            try createSearchIndex(db)
            try populateSearchIndex(db)
        }

        migrator.registerMigration("v4_tags") { db in
            try createTagTables(db)
        }

        migrator.registerMigration("v5_daily_unique") { db in
            try addDayColumn(db)
            try backfillDayColumn(db)
            try createDailyUniqueIndex(db)
        }

        migrator.registerMigration("v6_daily_day_from_observed") { db in
            try recomputeDayFromObserved(db)
        }

        return migrator
    }

    // MARK: v1

    private static func createNotebookTable(_ db: Database) throws {
        try db.create(table: "notebook") { t in
            t.primaryKey("id", .text)
            t.column("name", .text).notNull()
            t.column("parent_id", .text)
                .references("notebook", onDelete: .setNull)
            t.column("color_name", .text)
            t.column("sort_index", .integer).notNull().defaults(to: 0)
            t.column("created_at", .double).notNull()
            t.column("updated_at", .double).notNull()

            // V2 seams. Nothing reads these in V1, and adding them to a
            // shipped table would be a migration — adding them now is five
            // lines.
            t.column("owner_id", .text)
            t.column("local_version", .integer).notNull().defaults(to: 0)
            t.column("remote_version", .integer)
            t.column("deleted_at", .double)
            t.column("last_editor", .text)
        }

        // Reads filter tombstones and order siblings; both deserve an index
        // before there is enough data for the absence to be noticeable.
        try db.create(
            index: "notebook_on_parent_sort",
            on: "notebook",
            columns: ["parent_id", "sort_index"]
        )
    }

    private static func createJournalTable(_ db: Database) throws {
        // ⚠️ Created in v1 although nothing writes to it until 0.3.0. Adding a
        // table to a shipped schema is a migration; adding it now is free.
        try db.create(table: "journal") { t in
            // SQLite's own monotonic counter. The sync protocol trusts this
            // ordering and nothing else, so it is better assigned by the
            // database than by a caller that could restart at 1.
            t.autoIncrementedPrimaryKey("seq")
            t.column("id", .text).notNull().unique()
            t.column("subject_type", .text).notNull()
            t.column("subject_id", .text).notNull()
            t.column("operation", .text).notNull()
            t.column("payload", .blob).notNull()
            t.column("recorded_at", .double).notNull()
            t.column("owner_id", .text)
            t.column("last_editor", .text)
        }
    }

    // MARK: v2

    private static func createNoteTable(_ db: Database) throws {
        try db.create(table: "note") { t in
            t.primaryKey("id", .text)
            t.column("notebook_id", .text).notNull()
                .references("notebook", onDelete: .restrict)
            t.column("kind", .text).notNull()

            // Rich text is two columns, matching `RichText`'s two fields.
            //
            // The plain copy is not redundancy for its own sake: FTS cannot
            // index a blob, and a list row should not decode attributes to
            // draw a title. It is also what survives if the attribute format
            // ever changes.
            t.column("title_data", .blob)
            t.column("title_plain", .text).notNull()
            t.column("body_data", .blob)
            t.column("body_plain", .text).notNull()

            t.column("is_pinned", .integer).notNull().defaults(to: false)
            t.column("observed_at", .double)
            t.column("created_at", .double).notNull()
            t.column("updated_at", .double).notNull()

            t.column("owner_id", .text)
            t.column("local_version", .integer).notNull().defaults(to: 0)
            t.column("remote_version", .integer)
            t.column("deleted_at", .double)
            t.column("last_editor", .text)
        }

        // The two orderings every list uses: a notebook's notes, and a kind's.
        try db.create(
            index: "note_on_notebook_updated",
            on: "note",
            columns: ["notebook_id", "updated_at"]
        )
        try db.create(
            index: "note_on_kind_updated",
            on: "note",
            columns: ["kind", "updated_at"]
        )
    }

    // MARK: v3

    private static func createSearchIndex(_ db: Database) throws {
        // ⚠️ **Standalone, not external-content.**
        //
        // External content avoids duplicating the text, but needs an
        // INTEGER rowid join, the awkward
        // `INSERT INTO fts(fts, rowid, …) VALUES('delete', …)` form, and
        // triggers to stay in step. The text is tens of kilobytes per
        // thousand notes; duplicating it buys an index that cannot drift,
        // because the row and its entry are written in one transaction.
        //
        // `remove_diacritics 2` is what makes "heron" match "Herón" —
        // FR-1.3, and the acceptance test for it.
        try db.execute(sql: """
            CREATE VIRTUAL TABLE note_fts USING fts5(
                note_id UNINDEXED,
                title,
                body,
                tokenize = 'unicode61 remove_diacritics 2'
            )
            """)
    }

    /// Builds the index from the notes already on disk.
    ///
    /// 0.4.0 accepted index writes and discarded them, because there was
    /// nowhere to put them. This is the other half of that promise: every
    /// note written before FTS5 existed is indexed here, so nothing had to
    /// be remembered in the meantime.
    private static func populateSearchIndex(_ db: Database) throws {
        try db.execute(sql: """
            INSERT INTO note_fts (note_id, title, body)
            SELECT id, title_plain, body_plain
              FROM note
             WHERE deleted_at IS NULL
            """)
    }

    // MARK: v4

    private static func createTagTables(_ db: Database) throws {
        try db.create(table: "tag") { t in
            // The slug *is* the identity — see `TagID`. No surrogate key,
            // because two devices that have never met must agree on it.
            t.primaryKey("id", .text)
            t.column("label", .text).notNull()
            t.column("created_at", .double).notNull()
            t.column("updated_at", .double).notNull()

            t.column("owner_id", .text)
            t.column("local_version", .integer).notNull().defaults(to: 0)
            t.column("remote_version", .integer)
            t.column("deleted_at", .double)
            t.column("last_editor", .text)
        }

        try db.create(table: "note_tag") { t in
            t.column("note_id", .text).notNull()
                .references("note", onDelete: .cascade)
            t.column("tag_id", .text).notNull()
                .references("tag", onDelete: .cascade)

            // ⚠️ The order a person added tags is visible to them, and a plain
            // join returns rows in whatever order SQLite finds convenient. A
            // note whose tags reshuffle between reads looks like a bug in the
            // view that drew it.
            t.column("position", .integer).notNull().defaults(to: 0)

            t.primaryKey(["note_id", "tag_id"])
        }

        // "Which notes have this tag" is the filter's question, and it reads
        // the join backwards from its primary key.
        try db.create(
            index: "note_tag_on_tag",
            on: "note_tag",
            columns: ["tag_id"]
        )
    }

    // MARK: v5

    private static func addDayColumn(_ db: Database) throws {
        try db.alter(table: "note") { t in
            // Only daily notes carry one. A calendar day is not derivable from
            // an epoch second without a timezone, so it is stored rather than
            // computed on read.
            t.add(column: "day", .text)
        }
    }

    /// Fills in `day` for daily notes that predate this migration.
    ///
    /// There are none in practice — `NoteKind.daily` has existed since domain
    /// 0.4.0 but nothing created one. Doing it anyway costs three lines and
    /// means the index below cannot fail to build on a database that did.
    private static func backfillDayColumn(_ db: Database) throws {
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, created_at FROM note WHERE kind = 'daily' AND day IS NULL
            """)
        for row in rows {
            let created = Date(timeIntervalSince1970: row["created_at"])
            try db.execute(
                sql: "UPDATE note SET day = ? WHERE id = ?",
                arguments: [DayKey.string(for: created), row["id"] as String]
            )
        }
    }

    /// One daily note per day, enforced by the database.
    ///
    /// ⚠️ **The service also guards this, and both are needed.** A check in the
    /// service closes the window it can see; the index closes the one it
    /// cannot — two processes, or two taps racing inside one. The database is
    /// the thing that cannot be raced.
    ///
    /// Tombstones are excluded: deleting today's entry must not prevent
    /// writing another one.
    private static func createDailyUniqueIndex(_ db: Database) throws {
        try db.execute(sql: """
            CREATE UNIQUE INDEX note_daily_unique
                ON note(day)
             WHERE kind = 'daily' AND day IS NOT NULL AND deleted_at IS NULL
            """)
    }

    // MARK: v6

    /// Recomputes `day` from the moment a note is *about*, not the moment it
    /// was written.
    ///
    /// ⚠️ **v5 got this wrong, and v5 is not edited.** Its backfill read
    /// `created_at`, while `NoteRow` has always written `day` from
    /// `happenedAt` — which prefers `observed_at`. Two definitions of "which
    /// day", disagreeing: a daily entry written at 00:30 about yesterday
    /// landed on today if it was migrated, and on yesterday if it was saved
    /// fresh.
    ///
    /// A shipped migration is never edited — a device that already ran v5 has
    /// the old keys, and rewriting v5 would never reach it. So this corrects
    /// them, and v5 stays exactly as it shipped.
    ///
    /// 🧪 Found by the v1→v5 chain test, not by the per-migration ones: only a
    /// database carrying data from *before* a migration can show that the
    /// migration and the writer disagree.
    private static func recomputeDayFromObserved(_ db: Database) throws {
        try db.execute(sql: """
            UPDATE note
               SET day = strftime('%Y-%m-%d',
                                  COALESCE(observed_at, created_at),
                                  'unixepoch', 'localtime')
             WHERE kind = 'daily' AND deleted_at IS NULL
            """)
    }

    private static func seedDefaultNotebook(_ db: Database) throws {
        let now = Date().timeIntervalSince1970
        try db.execute(
            sql: """
                INSERT INTO notebook
                    (id, name, parent_id, color_name, sort_index,
                     created_at, updated_at, local_version)
                VALUES (?, ?, NULL, NULL, 0, ?, ?, 0)
                """,
            arguments: [
                DefaultNotebook.identifier.value.uuidString,
                DefaultNotebook.name,
                now,
                now,
            ]
        )
    }
}
