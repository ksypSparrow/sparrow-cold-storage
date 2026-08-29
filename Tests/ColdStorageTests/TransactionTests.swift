import Foundation
import SparrowDomain
import StorageContracts
import Testing
@testable import ColdStorage

@Suite("Transactions")
struct TransactionTests {
    struct Boom: Error {}

    @Test("A throwing body leaves nothing behind")
    func failedWriteRollsBackEverything() async throws {
        let storage = try ColdStorage.inMemory()
        let note = makeNote("Half-written")

        await #expect(throws: Boom.self) {
            try await storage.transactions.write { session in
                try await session.notes.insert(note)
                try await session.index.index(note)
                throw Boom()
            }
        }

        #expect(try await storage.notes.count() == 0)
        #expect(try await storage.notes.note(note.id) == nil)
    }

    @Test("A rollback also unwinds the index and the journal")
    func rollbackUnwindsIndexAndJournal() async throws {
        let storage = try ColdStorage.inMemory()
        let kept = makeNote("Kept", body: "heron", at: 0)
        try await storage.save(kept)

        await #expect(throws: Boom.self) {
            try await storage.transactions.write { session in
                let doomed = makeNote("Doomed", body: "heron", at: 60)
                try await session.notes.insert(doomed)
                try await session.index.index(doomed)
                try await session.journal.record(
                    JournalEntry(
                        sequence: 99,
                        subject: .note(doomed.id),
                        operation: .upsert,
                        payload: Data(),
                        recordedAt: doomed.updatedAt
                    )
                )
                throw Boom()
            }
        }

        let hits = try await storage.transactions.write { session in
            try await session.index.matches("heron", limit: 10)
        }
        #expect(hits == [kept.id])

        let pending = try await storage.transactions.write { session in
            try await session.journal.pending(limit: 10)
        }
        #expect(pending.count == 1)
    }

    @Test("Writes are serialised, so concurrent inserts all land")
    func concurrentWritesAreSerialised() async throws {
        let storage = try ColdStorage.inMemory()
        let notes = (0..<25).map { makeNote("Note \($0)", at: TimeInterval($0)) }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for note in notes {
                group.addTask { try await storage.save(note) }
            }
            try await group.waitForAll()
        }

        #expect(try await storage.notes.count() == 25)
    }
}
