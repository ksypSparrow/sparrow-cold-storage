import Foundation
import SparrowDomain
import StorageContracts
import Testing
@testable import ColdStorage

@Suite("Atomicity")
struct AtomicityTests {
    struct Boom: Error {}
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func draft(_ name: String) -> Notebook {
        Notebook(name: name, sortIndex: 0, createdAt: Self.now, updatedAt: Self.now)
    }

    /// The test the gate is written around. A notebook that was inserted and
    /// then failed to journal must not survive: a row with no journal entry is
    /// a change V2 will never learn about.
    @Test("A failure after the insert leaves the notebook table unchanged",
          arguments: StoreKind.allCases)
    func failureAfterInsertRollsBack(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let notebook = draft("Half-written")

        await #expect(throws: Boom.self) {
            try await fixture.storage.transactions.write { session in
                try session.notebooks.insert(notebook)
                try session.journal.record(
                    JournalDraft(
                        subject: .notebook(notebook.id),
                        operation: .upsert,
                        payload: Data(),
                        recordedAt: Self.now
                    )
                )
                throw Boom()
            }
        }

        #expect(try await fixture.storage.notebooks.notebook(notebook.id) == nil)
        #expect(try await fixture.storage.notebooks.allNotebooks().count == 1)
        #expect(try await fixture.storage.journal.pending(limit: 10).isEmpty)
    }

    @Test("A rolled-back transaction publishes nothing",
          arguments: StoreKind.allCases)
    func rollbackPublishesNothing(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        var events = fixture.storage.observer.changes.makeAsyncIterator()

        await #expect(throws: Boom.self) {
            try await fixture.storage.transactions.write { session in
                try session.notebooks.insert(self.draft("Doomed"))
                throw Boom()
            }
        }

        // The next event must be the *successful* write, not the failed one.
        let survivor = draft("Survivor")
        try await fixture.storage.transactions.write { session in
            try session.notebooks.insert(survivor)
        }
        #expect(await events.next() == .notebooks([survivor.id]))
    }

    @Test("A committed write announces what it touched",
          arguments: StoreKind.allCases)
    func commitPublishesTouchedIdentifiers(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        var events = fixture.storage.observer.changes.makeAsyncIterator()

        let notebook = draft("Observed")
        try await fixture.storage.transactions.write { session in
            try session.notebooks.insert(notebook)
        }

        #expect(await events.next() == .notebooks([notebook.id]))
    }

    /// A session that escapes its `write { }` is holding a database handle
    /// whose transaction has already committed. Using it would be a write
    /// outside any transaction — the one thing the whole design forbids.
    @Test("A session captured past write { } fails rather than corrupting",
          arguments: StoreKind.allCases)
    func escapedSessionIsDead(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)

        nonisolated(unsafe) var escaped: (any StorageSession)?
        try await fixture.storage.transactions.write { session in
            escaped = session
        }

        let session = try #require(escaped)
        #expect(throws: StorageError.self) {
            try session.notebooks.insert(self.draft("Smuggled"))
        }
        #expect(try await fixture.storage.notebooks.allNotebooks().count == 1)
    }
}

@Suite("Journal ordering")
struct JournalOrderingTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Sequence, never timestamp. A clock correction can move `recordedAt`
    /// backwards; the sync protocol would then replay changes out of order,
    /// and the last writer would not be the last write.
    @Test("Entries come back in sequence order even when timestamps go backwards",
          arguments: StoreKind.allCases)
    func orderingFollowsSequenceNotTime(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let ids = (0..<5).map { _ in NotebookID() }

        try await fixture.storage.transactions.write { session in
            for (offset, id) in ids.enumerated() {
                try session.journal.record(
                    JournalDraft(
                        subject: .notebook(id),
                        operation: .upsert,
                        payload: Data(),
                        // Deliberately descending: entry 0 is the newest.
                        recordedAt: Self.now.addingTimeInterval(
                            Double(-offset) * 60
                        )
                    )
                )
            }
        }

        let pending = try await fixture.storage.journal.pending(limit: 10)
        #expect(pending.map(\.sequence) == pending.map(\.sequence).sorted())
        #expect(pending.count == 5)

        let recorded = pending.compactMap { entry -> NotebookID? in
            if case .notebook(let id) = entry.subject { id } else { nil }
        }
        #expect(recorded == ids)
    }

    @Test("Sequence is assigned by storage, and strictly increases",
          arguments: StoreKind.allCases)
    func sequenceIsMonotonic(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)

        for _ in 0..<3 {
            try await fixture.storage.transactions.write { session in
                try session.journal.record(
                    JournalDraft(
                        subject: .notebook(NotebookID()),
                        operation: .upsert,
                        payload: Data(),
                        recordedAt: Self.now
                    )
                )
            }
        }

        let sequences = try await fixture.storage.journal
            .pending(limit: 10).map(\.sequence)
        #expect(sequences == [1, 2, 3])
        #expect(Set(sequences).count == 3)
    }
}
