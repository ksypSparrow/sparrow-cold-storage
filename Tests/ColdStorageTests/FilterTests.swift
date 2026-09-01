import Foundation
import GRDB
import SparrowDomain
import StorageContracts
import Testing
@testable import ColdStorage

@Suite("Filtering")
struct FilterTests {
    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func seed(_ storage: StorageSet) async throws -> [String: Note] {
        var made: [String: Note] = [:]
        let notes: [(String, NoteKind, Bool, TimeInterval)] = [
            ("pinned sketch", .sketch, true, 0),
            ("plain sketch", .sketch, false, 60),
            ("voice memo", .voice, false, 120),
            ("observation", .observation, true, 180),
        ]
        for (title, kind, pinned, offset) in notes {
            var note = makeNote(title, kind: kind, at: offset)
            note.isPinned = pinned
            try await storage.save(note)
            made[title] = note
        }
        return made
    }

    @Test(".all returns everything, newest first", arguments: StoreKind.allCases)
    func allReturnsEverything(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let notes = try await seed(fixture.storage)

        let found = try await fixture.storage.notes.notes(
            matching: .all, sort: .mostRecent, limit: 10
        )
        #expect(found.count == 4)
        #expect(found.first?.id == notes["observation"]?.id)
    }

    @Test("Filtering by notebook", arguments: StoreKind.allCases)
    func filterByNotebook(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        _ = try await seed(fixture.storage)
        let other = makeNotebook("Wetlands")
        try await fixture.storage.transactions.write { session in
            try session.notebooks.insert(other)
        }
        let elsewhere = makeNote("elsewhere", in: other.id, at: 240)
        try await fixture.storage.save(elsewhere)

        let found = try await fixture.storage.notes.notes(
            matching: NoteFilter(notebookID: other.id),
            sort: .mostRecent, limit: 10
        )
        #expect(found.map(\.id) == [elsewhere.id])
    }

    @Test("Filtering by one kind", arguments: StoreKind.allCases)
    func filterByOneKind(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        _ = try await seed(fixture.storage)

        let found = try await fixture.storage.notes.notes(
            matching: NoteFilter(kinds: [.voice]), sort: .mostRecent, limit: 10
        )
        #expect(found.map(\.plainTitle) == ["voice memo"])
    }

    @Test("Filtering by several kinds is an OR within the set",
          arguments: StoreKind.allCases)
    func filterBySeveralKinds(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        _ = try await seed(fixture.storage)

        let found = try await fixture.storage.notes.notes(
            matching: NoteFilter(kinds: [.voice, .observation]),
            sort: .mostRecent, limit: 10
        )
        #expect(Set(found.map(\.plainTitle)) == ["voice memo", "observation"])
    }

    /// An empty set means *any* kind. The natural SQL translation, `IN ()`, is
    /// both invalid SQLite and the opposite of what the filter means — so it
    /// has to compile to no clause at all.
    @Test("An empty kinds set matches every kind", arguments: StoreKind.allCases)
    func emptyKindsMatchesEverything(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        _ = try await seed(fixture.storage)

        let found = try await fixture.storage.notes.notes(
            matching: NoteFilter(kinds: []), sort: .mostRecent, limit: 10
        )
        #expect(found.count == 4)
    }

    @Test("Filtering by pin, both ways", arguments: StoreKind.allCases)
    func filterByPinned(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        _ = try await seed(fixture.storage)

        let pinned = try await fixture.storage.notes.notes(
            matching: NoteFilter(isPinned: true), sort: .mostRecent, limit: 10
        )
        let unpinned = try await fixture.storage.notes.notes(
            matching: NoteFilter(isPinned: false), sort: .mostRecent, limit: 10
        )
        #expect(Set(pinned.map(\.plainTitle)) == ["pinned sketch", "observation"])
        #expect(Set(unpinned.map(\.plainTitle)) == ["plain sketch", "voice memo"])
    }

    @Test("Filtering by creation window", arguments: StoreKind.allCases)
    func filterByCreatedWithin(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        _ = try await seed(fixture.storage)

        let window = DateInterval(
            start: Self.base.addingTimeInterval(30),
            end: Self.base.addingTimeInterval(150)
        )
        let found = try await fixture.storage.notes.notes(
            matching: NoteFilter(createdWithin: window),
            sort: .mostRecent, limit: 10
        )
        #expect(Set(found.map(\.plainTitle)) == ["plain sketch", "voice memo"])
    }

    @Test("Fields combine as AND", arguments: StoreKind.allCases)
    func fieldsCombineAsAnd(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        _ = try await seed(fixture.storage)

        let found = try await fixture.storage.notes.notes(
            matching: NoteFilter(kinds: [.sketch], isPinned: true),
            sort: .mostRecent, limit: 10
        )
        #expect(found.map(\.plainTitle) == ["pinned sketch"])
    }

    @Test("Text and properties apply together", arguments: StoreKind.allCases)
    func textAndPropertiesCombine(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        _ = try await seed(fixture.storage)

        let found = try await fixture.storage.notes.notes(
            matching: NoteFilter(text: "sketch", isPinned: true),
            sort: .mostRecent, limit: 10
        )
        #expect(found.map(\.plainTitle) == ["pinned sketch"])
    }

    @Test("Text filtering folds diacritics, like the search field",
          arguments: StoreKind.allCases)
    func textFilteringFoldsDiacritics(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let note = makeNote("Herón at dusk", at: 300)
        try await fixture.storage.save(note)

        let found = try await fixture.storage.notes.notes(
            matching: NoteFilter(text: "heron"), sort: .mostRecent, limit: 10
        )
        #expect(found.map(\.id) == [note.id])
    }

    /// One forgotten `deleted_at IS NULL` and a deleted note reappears in the
    /// Find action but nowhere else.
    @Test("Tombstones never match any filter", arguments: StoreKind.allCases)
    func tombstonesNeverMatch(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let notes = try await seed(fixture.storage)
        let doomed = try #require(notes["voice memo"])

        try await fixture.storage.transactions.write { session in
            try session.notes.markDeleted(doomed.id, at: Date())
            try session.index.remove(doomed.id)
        }

        for filter in [
            NoteFilter.all,
            NoteFilter(kinds: [.voice]),
            NoteFilter(text: "voice"),
            NoteFilter(isPinned: false),
        ] {
            let found = try await fixture.storage.notes.notes(
                matching: filter, sort: .mostRecent, limit: 10
            )
            #expect(!found.contains { $0.id == doomed.id })
        }
    }

    @Test("count(matching:) agrees with the fetch",
          arguments: StoreKind.allCases)
    func countAgreesWithFetch(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        _ = try await seed(fixture.storage)

        for filter in [
            NoteFilter.all,
            NoteFilter(kinds: [.sketch]),
            NoteFilter(isPinned: true),
            NoteFilter(text: "sketch"),
        ] {
            let counted = try await fixture.storage.notes.count(matching: filter)
            let fetched = try await fixture.storage.notes.notes(
                matching: filter, sort: .mostRecent, limit: 1_000
            )
            #expect(counted == fetched.count)
        }
    }

    @Test("The limit is honoured", arguments: StoreKind.allCases)
    func limitIsHonoured(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        _ = try await seed(fixture.storage)

        #expect(try await fixture.storage.notes.notes(
            matching: .all, sort: .mostRecent, limit: 2
        ).count == 2)
        #expect(try await fixture.storage.notes.notes(
            matching: .all, sort: .mostRecent, limit: 0
        ).isEmpty)
    }
}

@Suite("Sorting")
struct SortingTests {
    private func seed(_ storage: StorageSet) async throws {
        for (title, offset) in [("beta", 0.0), ("Alpha", 60.0), ("gamma", 120.0)] {
            try await storage.save(makeNote(title, at: offset))
        }
    }

    @Test("Every field and order agrees with the domain's own ordering",
          arguments: StoreKind.allCases)
    func sortMatchesTheDomain(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        try await seed(fixture.storage)

        // The domain defines the order; SQL has to reproduce it. Comparing
        // against `NoteSort.orders` rather than a hand-written expectation is
        // what stops the two definitions drifting.
        let everything = try await fixture.storage.notes.notes(
            matching: .all, sort: .mostRecent, limit: 100
        )

        for field in NoteSort.Field.allCases {
            for order in NoteSort.Order.allCases {
                let sort = NoteSort(field: field, order: order)
                let fromStore = try await fixture.storage.notes.notes(
                    matching: .all, sort: sort, limit: 100
                )
                let expected = everything.sorted(by: sort.orders)
                #expect(
                    fromStore.map(\.id) == expected.map(\.id),
                    "\(field) \(order) disagreed"
                )
            }
        }
    }
}

@Suite("FilterCompiler")
struct FilterCompilerTests {
    @Test("The tombstone check is always present")
    func tombstoneCheckIsAlwaysThere() {
        for filter in [
            NoteFilter.all,
            NoteFilter(kinds: [.sketch]),
            NoteFilter(isPinned: true),
        ] {
            #expect(
                FilterCompiler.predicate(for: filter).sql
                    .contains("n.deleted_at IS NULL")
            )
        }
    }

    @Test("An empty filter compiles to the tombstone check alone")
    func emptyFilterIsJustTheTombstoneCheck() {
        let predicate = FilterCompiler.predicate(for: .all)
        #expect(predicate.sql == "n.deleted_at IS NULL")
    }

    @Test("An empty kinds set produces no IN clause")
    func emptyKindsProducesNoClause() {
        #expect(!FilterCompiler.predicate(for: NoteFilter(kinds: [])).sql
            .contains("IN"))
    }

    /// A filter is built from whatever a Shortcut passed in. One interpolated
    /// quote is the whole class of bug, so every value is bound.
    @Test("Values are bound, never interpolated")
    func valuesAreBound() {
        let hostile = "'; DROP TABLE note; --"
        let filter = NoteFilter(text: hostile, notebookID: NotebookID())
        let predicate = FilterCompiler.predicate(for: filter)

        #expect(!predicate.sql.contains("DROP"))
        #expect(!predicate.sql.contains("'"))
        #expect(predicate.sql.contains("?"))
    }

    @Test("A hostile filter runs safely against a real database")
    func hostileFilterIsHarmless() async throws {
        let fixture = try StoreFixture(.onDisk)
        let note = makeNote("Kingfisher")
        try await fixture.storage.save(note)

        for hostile in [
            "'; DROP TABLE note; --",
            "\" OR 1=1 --",
            "%",
            "_",
        ] {
            _ = try await fixture.storage.notes.notes(
                matching: NoteFilter(text: hostile), sort: .mostRecent, limit: 10
            )
        }

        // The table is still there, with its note in it.
        #expect(try await fixture.storage.notes.count() == 1)
    }

    @Test("Every sort field compiles to an order clause with a tiebreak",
          arguments: NoteSort.Field.allCases)
    func everyFieldHasATiebreak(field: NoteSort.Field) {
        for order in NoteSort.Order.allCases {
            let clause = FilterCompiler.orderClause(
                for: NoteSort(field: field, order: order)
            )
            #expect(clause.hasPrefix("ORDER BY"))
            #expect(clause.contains("n.id"))
        }
    }
}

@Suite("Filter dispatch")
struct FilterDispatchTests {
    /// A filter with no text must not touch the index at all. Proving it by
    /// dropping the FTS table is blunt, but it is the only check that cannot
    /// be satisfied by a join that happens to be harmless.
    @Test("A filter without text never touches the index")
    func textFreeFilterSkipsTheIndex() async throws {
        try await withTemporaryDatabase { url in
            let storage = try SQLiteStorage(at: url)
            let note = makeNote("Kingfisher", kind: .sketch)
            try await storage.pool.write { db in try NoteRow(note).insert(db) }
            try await storage.pool.write { db in
                try db.execute(sql: "DROP TABLE note_fts")
            }

            let repository = SQLiteNoteRepository(storage: storage)
            let found = try await repository.notes(
                matching: NoteFilter(kinds: [.sketch]),
                sort: .mostRecent,
                limit: 10
            )
            #expect(found.map(\.id) == [note.id])
        }
    }

    /// …and one *with* text must, which is what makes the check above mean
    /// something.
    @Test("A filter with text does touch the index")
    func textFilterUsesTheIndex() async throws {
        try await withTemporaryDatabase { url in
            let storage = try SQLiteStorage(at: url)
            try await storage.pool.write { db in
                try NoteRow(makeNote("Kingfisher")).insert(db)
                try db.execute(sql: "DROP TABLE note_fts")
            }

            let repository = SQLiteNoteRepository(storage: storage)
            await #expect(throws: (any Error).self) {
                try await repository.notes(
                    matching: NoteFilter(text: "kingfisher"),
                    sort: .mostRecent,
                    limit: 10
                )
            }
        }
    }
}
