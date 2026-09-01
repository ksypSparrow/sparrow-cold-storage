import Foundation
import GRDB
import SparrowDomain
import StorageContracts

/// Note reads from outside a transaction.
struct SQLiteNoteRepository: NoteReading {
    let storage: SQLiteStorage

    func note(_ id: NoteID) async throws -> Note? {
        try await storage.read { db in
            guard let row = try NoteRow.live()
                .filter(Column("id") == id.value.uuidString)
                .fetchOne(db)
            else { return nil }
            return try row.toDomain(tagIDs: NoteTags.read(id, from: db))
        }
    }

    func notes(_ ids: [NoteID]) async throws -> [Note] {
        let strings = ids.map(\.value.uuidString)
        guard !strings.isEmpty else { return [] }

        let found = try await storage.read { db in
            let rows = try NoteRow.live()
                .filter(strings.contains(Column("id")))
                .fetchAll(db)
            return try Self.withTags(rows, in: db)
        }
        // Return them in the order asked for, not the order SQLite found them.
        // A caller that passed identifiers in a considered order gets it back.
        let byID = Dictionary(
            uniqueKeysWithValues: found.map { ($0.id.value.uuidString, $0) }
        )
        return strings.compactMap { byID[$0] }
    }

    func recentNotes(limit: Int) async throws -> [Note] {
        guard limit > 0 else { return [] }
        return try await storage.read { db in
            let rows = try NoteRow.live()
                .order(Column("updated_at").desc, Column("id"))
                .limit(limit)
                .fetchAll(db)
            return try Self.withTags(rows, in: db)
        }
    }

    func notes(
        matching filter: NoteFilter,
        sort: NoteSort,
        limit: Int
    ) async throws -> [Note] {
        guard limit > 0 else { return [] }
        return try await fetch(
            filter,
            order: FilterCompiler.orderClause(for: sort),
            limit: limit
        )
    }

    func count(matching filter: NoteFilter) async throws -> Int {
        let predicate = FilterCompiler.predicate(for: filter)
        var arguments = predicate.arguments

        // ⚠️ One statement, not two.
        //
        // The plan describes running FTS first and intersecting the result.
        // A join does the same thing and is strictly better: the LIMIT applies
        // after *both* filters, so a text search that matches ten thousand
        // notes does not have to materialise ten thousand identifiers to
        // return twenty. It also lets SQLite choose the order to apply them.
        let (join, matchClause) = textJoin(for: filter, arguments: &arguments)

        return try await storage.read { [arguments] db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM note n
                \(join)
                 WHERE \(predicate.sql)\(matchClause)
                """, arguments: arguments) ?? 0
        }
    }

    /// Rows plus their tags, in one extra query rather than one per note.
    static func withTags(_ rows: [NoteRow], in db: Database) throws -> [Note] {
        let ids = rows.compactMap { UUID(uuidString: $0.id).map(NoteID.init) }
        let tags = try NoteTags.read(ids, from: db)
        return try rows.map { row in
            let id = UUID(uuidString: row.id).map(NoteID.init)
            return try row.toDomain(tagIDs: id.flatMap { tags[$0] } ?? [])
        }
    }

    private func fetch(
        _ filter: NoteFilter,
        order: String,
        limit: Int
    ) async throws -> [Note] {
        let predicate = FilterCompiler.predicate(for: filter)
        var arguments = predicate.arguments
        let (join, matchClause) = textJoin(for: filter, arguments: &arguments)
        arguments += [limit]

        return try await storage.read { [arguments] db in
            let rows = try NoteRow.fetchAll(db, sql: """
                SELECT n.* FROM note n
                \(join)
                 WHERE \(predicate.sql)\(matchClause)
                \(order)
                 LIMIT ?
                """, arguments: arguments)
            return try Self.withTags(rows, in: db)
        }
    }

    /// The FTS half, present only when the filter actually asks for text.
    /// A filter with no text never touches the index.
    private func textJoin(
        for filter: NoteFilter,
        arguments: inout StatementArguments
    ) -> (join: String, matchClause: String) {
        guard filter.requiresTextSearch,
              let text = filter.text,
              let query = FTSQuery.make(from: text)
        else {
            return ("", "")
        }
        arguments += [query]
        return ("JOIN note_fts f ON f.note_id = n.id", " AND note_fts MATCH ?")
    }
}

extension NoteRow {
    /// Every read filters tombstones. A soft-deleted note must never surface,
    /// which is easy to forget one query at a time.
    static func live() -> QueryInterfaceRequest<NoteRow> {
        NoteRow.filter(Column("deleted_at") == nil)
    }
}
