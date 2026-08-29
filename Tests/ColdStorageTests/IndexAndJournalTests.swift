import Foundation
import SparrowDomain
import StorageContracts
import Testing
@testable import ColdStorage

@Suite("Index and journal")
struct IndexAndJournalTests {
    @Test("Indexed content is found case-insensitively")
    func indexMatchesCaseInsensitively() async throws {
        let storage = try ColdStorage.inMemory()
        try await storage.save(makeNote("Kingfisher", body: "North Bank"))

        let hits = try await storage.transactions.write { session in
            try await session.index.matches("north bank", limit: 10)
        }
        #expect(hits.count == 1)
    }

    @Test("Empty search text matches nothing rather than everything")
    func emptySearchMatchesNothing() async throws {
        let storage = try ColdStorage.inMemory()
        try await storage.save(makeNote("Kingfisher"))

        let hits = try await storage.transactions.write { session in
            try await session.index.matches("   ", limit: 10)
        }
        #expect(hits.isEmpty)
    }

    @Test("A tombstoned note disappears from reads and from the index")
    func tombstoneHidesTheNote() async throws {
        let storage = try ColdStorage.inMemory()
        let note = makeNote("Deleted", body: "heron")
        try await storage.save(note)

        try await storage.transactions.write { session in
            try await session.notes.markDeleted(note.id, at: Date())
            try await session.index.remove(note.id)
        }

        #expect(try await storage.notes.note(note.id) == nil)
        #expect(try await storage.notes.count() == 0)

        let hits = try await storage.transactions.write { session in
            try await session.index.matches("heron", limit: 10)
        }
        #expect(hits.isEmpty)
    }

    @Test("The journal keeps a delete entry after the note is gone")
    func journalOutlivesTheNote() async throws {
        let storage = try ColdStorage.inMemory()
        let note = makeNote("Deleted")
        try await storage.save(note)

        try await storage.transactions.write { session in
            try await session.notes.markDeleted(note.id, at: note.updatedAt)
            try await session.journal.record(
                JournalEntry(
                    sequence: 2,
                    subject: .note(note.id),
                    operation: .delete,
                    payload: Data(),
                    recordedAt: note.updatedAt
                )
            )
        }

        let pending = try await storage.transactions.write { session in
            try await session.journal.pending(limit: 10)
        }
        #expect(pending.map(\.operation) == [.upsert, .delete])
        #expect(pending.allSatisfy { $0.subject == .note(note.id) })
    }

    @Test("Cleared entries do not come back")
    func clearedEntriesAreGone() async throws {
        let storage = try ColdStorage.inMemory()
        try await storage.save(makeNote("Journalled"))

        try await storage.transactions.write { session in
            let pending = try await session.journal.pending(limit: 10)
            try await session.journal.clear(pending.map(\.id))
        }

        let remaining = try await storage.transactions.write { session in
            try await session.journal.pending(limit: 10)
        }
        #expect(remaining.isEmpty)
    }
}
