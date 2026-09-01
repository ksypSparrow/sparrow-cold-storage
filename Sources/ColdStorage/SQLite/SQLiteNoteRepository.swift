import Foundation
import GRDB
import SparrowDomain
import StorageContracts

/// Note reads from outside a transaction.
struct SQLiteNoteRepository: NoteReading {
    let storage: SQLiteStorage

    func note(_ id: NoteID) async throws -> Note? {
        try await storage.read { db in
            try NoteRow.live()
                .filter(Column("id") == id.value.uuidString)
                .fetchOne(db)
        }?.toDomain()
    }

    func notes(_ ids: [NoteID]) async throws -> [Note] {
        let strings = ids.map(\.value.uuidString)
        guard !strings.isEmpty else { return [] }

        let found = try await storage.read { db in
            try NoteRow.live()
                .filter(strings.contains(Column("id")))
                .fetchAll(db)
        }
        // Return them in the order asked for, not the order SQLite found them.
        // A caller that passed identifiers in a considered order gets it back.
        let byID = Dictionary(
            uniqueKeysWithValues: try found.map { ($0.id, try $0.toDomain()) }
        )
        return strings.compactMap { byID[$0] }
    }

    func recentNotes(limit: Int) async throws -> [Note] {
        guard limit > 0 else { return [] }
        return try await storage.read { db in
            try NoteRow.live()
                .order(Column("updated_at").desc, Column("id"))
                .limit(limit)
                .fetchAll(db)
        }.map { try $0.toDomain() }
    }

    func count() async throws -> Int {
        try await storage.read { db in try NoteRow.live().fetchCount(db) }
    }
}

extension NoteRow {
    /// Every read filters tombstones. A soft-deleted note must never surface,
    /// which is easy to forget one query at a time.
    static func live() -> QueryInterfaceRequest<NoteRow> {
        NoteRow.filter(Column("deleted_at") == nil)
    }
}
