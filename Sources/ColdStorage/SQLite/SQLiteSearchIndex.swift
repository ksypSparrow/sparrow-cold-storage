import Foundation
import GRDB
import SparrowDomain
import StorageContracts

/// Maintaining the FTS index inside a transaction, so a note and its entry
/// commit together or not at all.
struct SQLiteIndexSession: SearchIndexWriting {
    let db: Database
    let validity: SessionValidity

    func index(_ note: Note) throws {
        try validity.check()
        // Delete-then-insert rather than upsert: an FTS5 table has no unique
        // constraint to conflict on, so this is the only way to make
        // re-indexing idempotent.
        try remove(note.id)
        try db.execute(
            sql: """
                INSERT INTO note_fts (note_id, title, body)
                VALUES (?, ?, ?)
                """,
            arguments: [
                note.id.value.uuidString,
                note.plainTitle,
                note.plainBody,
            ]
        )
    }

    func remove(_ id: NoteID) throws {
        try validity.check()
        try db.execute(
            sql: "DELETE FROM note_fts WHERE note_id = ?",
            arguments: [id.value.uuidString]
        )
    }
}

/// Searching, from outside a transaction.
struct SQLiteSearchIndex: SearchIndexing {
    let storage: SQLiteStorage

    func matches(_ text: String, limit: Int) async throws -> [NoteID] {
        guard limit > 0, let query = FTSQuery.make(from: text) else { return [] }

        let ids = try await storage.read { db in
            // Joined to `note` for two reasons: to exclude tombstones, and to
            // order by recency. For field notes the most recent sighting is
            // usually the wanted one, and it keeps both stores answering in
            // the same order — bm25 relevance would be a later choice.
            try String.fetchAll(db, sql: """
                SELECT f.note_id
                  FROM note_fts f
                  JOIN note n ON n.id = f.note_id
                 WHERE note_fts MATCH ?
                   AND n.deleted_at IS NULL
                 ORDER BY n.updated_at DESC, n.id
                 LIMIT ?
                """, arguments: [query, limit])
        }

        return try ids.map { string in
            guard let uuid = UUID(uuidString: string) else {
                throw StorageError.corrupted(
                    "note_fts.note_id is not a UUID: \(string)"
                )
            }
            return NoteID(uuid)
        }
    }

    func rebuild() async throws {
        _ = try await storage.write { db in
            try db.execute(sql: "DELETE FROM note_fts")
            try db.execute(sql: """
                INSERT INTO note_fts (note_id, title, body)
                SELECT id, title_plain, body_plain
                  FROM note
                 WHERE deleted_at IS NULL
                """)
        }
    }
}

/// Turns what a person typed into something FTS5 will accept.
///
/// ⚠️ Raw input cannot go into `MATCH`. FTS5 has its own query syntax, so an
/// apostrophe, a stray `"` or the word `AND` would either change the meaning
/// of the search or make it throw. Every term is quoted, which disarms the
/// syntax, and every term gets a `*` so search-as-you-type finds a note before
/// the word is finished.
enum FTSQuery {
    static func make(from text: String) -> String? {
        let terms = text
            .split(whereSeparator: \.isWhitespace)
            .map { $0.replacingOccurrences(of: "\"", with: "\"\"") }
            .filter { !$0.isEmpty }
            .map { "\"\($0)\"*" }

        guard !terms.isEmpty else { return nil }
        // Terms are ANDed: "heron bank" finds notes containing both.
        return terms.joined(separator: " ")
    }
}
