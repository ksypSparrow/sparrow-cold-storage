import Foundation
internal import GRDB
import SparrowDomain
import StorageContracts

/// Appending to the journal, inside a transaction.
struct SQLiteJournalSession: ChangeJournalWriting {
    let db: Database
    let validity: SessionValidity

    @discardableResult
    func record(_ draft: JournalDraft) throws -> JournalEntry {
        try validity.check()
        var row = JournalRow(draft, id: UUID())
        try row.insert(db)
        // `seq` comes back from SQLite's own counter, never from the caller.
        row.seq = db.lastInsertedRowID
        return try row.toDomain()
    }
}

/// Reading the journal, from outside one.
struct SQLiteJournalReader: ChangeJournaling {
    let storage: SQLiteStorage

    func pending(limit: Int) async throws -> [JournalEntry] {
        guard limit > 0 else { return [] }
        return try await storage.read { db in
            try JournalRow
                .order(Column("seq"))
                .limit(limit)
                .fetchAll(db)
        }.map { try $0.toDomain() }
    }

    func clear(_ ids: [JournalEntry.ID]) async throws {
        let strings = ids.map(\.uuidString)
        guard !strings.isEmpty else { return }
        _ = try await storage.write { db in
            try JournalRow
                .filter(strings.contains(Column("id")))
                .deleteAll(db)
        }
    }
}
