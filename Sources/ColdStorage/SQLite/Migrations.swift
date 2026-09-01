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
