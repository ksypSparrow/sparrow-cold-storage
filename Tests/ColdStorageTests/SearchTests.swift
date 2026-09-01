import Foundation
import SparrowDomain
import StorageContracts
import Testing
@testable import ColdStorage

@Suite("Full-text search")
struct SearchTests {
    private func save(
        _ title: String,
        body: String = "",
        at offset: TimeInterval = 0,
        to storage: StorageSet
    ) async throws -> Note {
        let note = makeNote(title, body: body, at: offset)
        try await storage.save(note)
        return note
    }

    /// **FR-1.3, and the acceptance test for it.** A person who saw a heron
    /// does not type the accent, and a person who did should still find it.
    @Test("Diacritics are ignored in both directions",
          arguments: StoreKind.allCases)
    func diacriticsAreIgnored(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let accented = try await save("Herón at dusk", to: fixture.storage)
        let plain = try await save("heron at dawn", at: 60, to: fixture.storage)

        let found = try await fixture.storage.search.matches("heron", limit: 10)
        #expect(Set(found) == [accented.id, plain.id])

        let foundAccented = try await fixture.storage.search
            .matches("herón", limit: 10)
        #expect(Set(foundAccented) == [accented.id, plain.id])
    }

    @Test("Search ignores case", arguments: StoreKind.allCases)
    func caseIsIgnored(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let note = try await save("Kingfisher", to: fixture.storage)

        for query in ["kingfisher", "KINGFISHER", "KingFisher"] {
            let found = try await fixture.storage.search.matches(query, limit: 10)
            #expect(found == [note.id], "failed for \(query)")
        }
    }

    @Test("The body is searched, not just the title",
          arguments: StoreKind.allCases)
    func bodyIsSearched(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let note = try await save(
            "Tuesday", body: "A heron on the north bank", to: fixture.storage
        )

        let found = try await fixture.storage.search.matches("heron", limit: 10)
        #expect(found == [note.id])
    }

    @Test("Empty or whitespace search matches nothing",
          arguments: StoreKind.allCases)
    func emptySearchMatchesNothing(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        _ = try await save("Kingfisher", to: fixture.storage)

        for query in ["", "   ", "\n"] {
            #expect(try await fixture.storage.search.matches(query, limit: 10).isEmpty)
        }
    }

    @Test("A word that appears nowhere matches nothing",
          arguments: StoreKind.allCases)
    func unmatchedWordFindsNothing(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        _ = try await save("Kingfisher", to: fixture.storage)

        #expect(try await fixture.storage.search.matches("albatross", limit: 10).isEmpty)
    }

    @Test("Results are newest first and honour the limit",
          arguments: StoreKind.allCases)
    func resultsAreOrderedAndLimited(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        _ = try await save("heron one", at: 0, to: fixture.storage)
        let middle = try await save("heron two", at: 60, to: fixture.storage)
        let newest = try await save("heron three", at: 120, to: fixture.storage)

        let found = try await fixture.storage.search.matches("heron", limit: 2)
        #expect(found == [newest.id, middle.id])
    }

    /// One forgotten `deleted_at IS NULL` and a deleted note reappears in
    /// search but nowhere else — the hardest kind of inconsistency to notice.
    @Test("A tombstoned note leaves the index in the same transaction",
          arguments: StoreKind.allCases)
    func tombstonesLeaveTheIndex(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let note = try await save("heron here", to: fixture.storage)
        let survivor = try await save("heron there", at: 60, to: fixture.storage)

        try await fixture.storage.transactions.write { session in
            try session.notes.markDeleted(note.id, at: Date())
            try session.index.remove(note.id)
        }

        let found = try await fixture.storage.search.matches("heron", limit: 10)
        #expect(found == [survivor.id])
    }

    @Test("Editing a note updates the index atomically",
          arguments: StoreKind.allCases)
    func editsReindex(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let note = try await save("kingfisher", to: fixture.storage)

        try await fixture.storage.transactions.write { session in
            var edited = note
            edited.title = RichText(plain: "albatross")
            try session.notes.update(edited)
            try session.index.index(edited)
        }

        #expect(try await fixture.storage.search.matches("kingfisher", limit: 10).isEmpty)
        #expect(try await fixture.storage.search.matches("albatross", limit: 10) == [note.id])
    }

    /// The index and the row commit together, or neither does. A failure
    /// after indexing must not leave a searchable note that does not exist.
    @Test("A rolled-back write leaves nothing in the index",
          arguments: StoreKind.allCases)
    func rollbackUnwindsTheIndex(kind: StoreKind) async throws {
        struct Boom: Error {}
        let fixture = try StoreFixture(kind)

        await #expect(throws: Boom.self) {
            try await fixture.storage.transactions.write { session in
                let doomed = makeNote("heron doomed")
                try session.notes.insert(doomed)
                try session.index.index(doomed)
                throw Boom()
            }
        }

        #expect(try await fixture.storage.search.matches("heron", limit: 10).isEmpty)
    }

    @Test("rebuild() reproduces the index exactly",
          arguments: StoreKind.allCases)
    func rebuildReproducesTheIndex(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let first = try await save("heron one", at: 0, to: fixture.storage)
        let second = try await save("heron two", at: 60, to: fixture.storage)

        let before = try await fixture.storage.search.matches("heron", limit: 10)
        try await fixture.storage.search.rebuild()
        let after = try await fixture.storage.search.matches("heron", limit: 10)

        #expect(before == after)
        #expect(Set(after) == [first.id, second.id])
    }

    @Test("Several terms are ANDed", arguments: StoreKind.allCases)
    func termsAreAnded(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let both = try await save(
            "heron", body: "north bank", at: 60, to: fixture.storage
        )
        _ = try await save("heron", body: "south shore", to: fixture.storage)

        let found = try await fixture.storage.search.matches("heron north", limit: 10)
        #expect(found == [both.id])
    }
}

@Suite("FTS query building")
struct FTSQueryTests {
    /// Raw input cannot reach `MATCH`. FTS5 has its own syntax, so an
    /// apostrophe, a stray quote or a bare `AND` would change the meaning of
    /// the search or make it throw.
    @Test("Dangerous input is disarmed rather than rejected",
          arguments: [
            "heron\"", "he\"ron", "AND", "OR heron", "NEAR(a b)", "*", "^heron",
          ])
    func syntaxIsDisarmed(input: String) async throws {
        let fixture = try StoreFixture(.onDisk)
        try await fixture.storage.save(makeNote("Kingfisher"))

        // The assertion is that this does not throw. Whether it matches is
        // beside the point — a search box must never crash on punctuation.
        _ = try await fixture.storage.search.matches(input, limit: 10)
    }

    @Test("Whitespace-only input yields no query")
    func whitespaceYieldsNothing() {
        #expect(FTSQuery.make(from: "   ") == nil)
        #expect(FTSQuery.make(from: "") == nil)
    }

    @Test("Terms are quoted and given a prefix marker")
    func termsAreQuotedAndPrefixed() {
        #expect(FTSQuery.make(from: "heron") == "\"heron\"*")
        #expect(FTSQuery.make(from: "heron bank") == "\"heron\"* \"bank\"*")
    }

    /// Search-as-you-type: a note should be findable before the word is done.
    @Test("A prefix finds the whole word")
    func prefixMatches() async throws {
        let fixture = try StoreFixture(.onDisk)
        let note = makeNote("Kingfisher")
        try await fixture.storage.save(note)

        #expect(try await fixture.storage.search.matches("king", limit: 10) == [note.id])
    }
}
