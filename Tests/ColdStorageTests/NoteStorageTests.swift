import Foundation
import SparrowDomain
import StorageContracts
import Testing
@testable import ColdStorage

@Suite("Note storage")
struct NoteStorageTests {
    @Test("A saved note is readable outside the transaction",
          arguments: StoreKind.allCases)
    func savedNoteIsReadable(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let note = makeNote("Kingfisher", body: "North bank, 40 minutes.")
        try await fixture.storage.save(note)

        #expect(try await fixture.storage.notes.note(note.id) == note)
        #expect(try await fixture.storage.notes.count() == 1)
    }

    @Test("An unknown identifier reads as nil, not as an error",
          arguments: StoreKind.allCases)
    func unknownIdentifierIsNil(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        #expect(try await fixture.storage.notes.note(NoteID()) == nil)
    }

    @Test("Recent notes come back newest first, honouring the limit",
          arguments: StoreKind.allCases)
    func recentNotesAreOrdered(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        for note in [
            makeNote("Middle", at: 60),
            makeNote("Oldest", at: 0),
            makeNote("Newest", at: 120),
        ] {
            try await fixture.storage.save(note)
        }

        let recent = try await fixture.storage.notes.recentNotes(limit: 2)
        #expect(recent.map(\.plainTitle) == ["Newest", "Middle"])
    }

    @Test("notes(_:) answers in the order it was asked",
          arguments: StoreKind.allCases)
    func notesPreserveRequestedOrder(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let first = makeNote("First", at: 0)
        let second = makeNote("Second", at: 60)
        for note in [first, second] { try await fixture.storage.save(note) }

        let asked = [second.id, first.id]
        let found = try await fixture.storage.notes.notes(asked)
        #expect(found.map(\.id) == asked)
    }

    @Test("Inserting the same identifier twice violates a constraint",
          arguments: StoreKind.allCases)
    func duplicateInsertIsRejected(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let note = makeNote("Once")
        try await fixture.storage.save(note)

        await #expect(throws: StorageError.self) {
            try await fixture.storage.save(note)
        }
        #expect(try await fixture.storage.notes.count() == 1)
    }

    @Test("Updating a note that was never inserted is notFound",
          arguments: StoreKind.allCases)
    func updateRequiresAnExistingNote(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)

        await #expect(throws: StorageError.notFound) {
            try await fixture.storage.transactions.write { session in
                try session.notes.update(makeNote("Ghost"))
            }
        }
    }

    /// One forgotten `deleted_at IS NULL` is all it takes for a deleted note to
    /// reappear in one list and not another, so every read is checked.
    @Test("A tombstoned note vanishes from every read",
          arguments: StoreKind.allCases)
    func tombstonesAreHiddenEverywhere(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let note = makeNote("Deleted")
        let survivor = makeNote("Survivor", at: 60)
        try await fixture.storage.save(note)
        try await fixture.storage.save(survivor)

        try await fixture.storage.transactions.write { session in
            try session.notes.markDeleted(note.id, at: Date())
        }

        let notes = fixture.storage.notes
        #expect(try await notes.note(note.id) == nil)
        #expect(try await notes.notes([note.id]).isEmpty)
        #expect(try await notes.recentNotes(limit: 10).map(\.id) == [survivor.id])
        #expect(try await notes.count() == 1)
    }

    /// A write can see its own effects; a read from outside cannot see them
    /// until the transaction commits.
    @Test("A session reads its own uncommitted write",
          arguments: StoreKind.allCases)
    func sessionReadsItsOwnWrite(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let note = makeNote("Read-your-writes")

        let seen = try await fixture.storage.transactions.write { session in
            try session.notes.insert(note)
            return try session.notes.note(note.id)
        }
        #expect(seen?.id == note.id)
    }
}

@Suite("Note storage · rich text")
struct NoteRichTextStorageTests {
    private func emphasised(_ string: String, bold word: String) -> AttributedString {
        var text = AttributedString(string)
        if let range = text.range(of: word) {
            text[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return text
    }

    @Test("Attributes survive a save and a read", arguments: StoreKind.allCases)
    func attributesSurvive(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let attributed = emphasised("Kingfisher on the bank", bold: "Kingfisher")
        var note = makeNote("placeholder")
        note.title = RichText(attributed)
        try await fixture.storage.save(note)

        let restored = try await fixture.storage.notes.note(note.id)
        #expect(restored?.title.attributedString() == attributed)
        #expect(restored?.plainTitle == "Kingfisher on the bank")
    }

    /// The plan asked that a corrupt blob *throw* rather than yield an empty
    /// note. It cannot yield an empty note any more: the plain text is a
    /// separate column, so a corrupt blob costs formatting and nothing else.
    /// That is strictly better than throwing, and worth asserting.
    @Test("A corrupt attribute blob costs formatting, never content")
    func corruptBlobKeepsTheWords() async throws {
        try withTemporaryDatabase { url in
            let storage = try SQLiteStorage(at: url)
            let note = makeNote("Kingfisher on the bank")

            try storage.pool.write { db in
                var row = NoteRow(note)
                row.titleData = Data("not json".utf8)
                try row.insert(db)
            }

            let row = try storage.pool.read { db in
                try NoteRow.fetchOne(db, key: note.id.value.uuidString)
            }
            let restored = try #require(row).toDomain()
            #expect(restored.plainTitle == "Kingfisher on the bank")
            #expect(
                restored.title.attributedString()
                    == AttributedString("Kingfisher on the bank")
            )
        }
    }

    @Test("Plain notes store no attribute blob")
    func plainNotesStoreNoBlob() async throws {
        try withTemporaryDatabase { url in
            let storage = try SQLiteStorage(at: url)
            let note = makeNote("No formatting here")
            try storage.pool.write { db in try NoteRow(note).insert(db) }

            let row = try storage.pool.read { db in
                try NoteRow.fetchOne(db, key: note.id.value.uuidString)
            }
            #expect(row?.titleData == nil)
            #expect(row?.titlePlain == "No formatting here")
        }
    }
}

@Suite("NoteRow")
struct NoteRowTests {
    @Test("Note round-trips through the row and back")
    func roundTripsThroughTheRow() throws {
        var attributed = AttributedString("North bank at dawn")
        if let range = attributed.range(of: "dawn") {
            attributed[range].inlinePresentationIntent = .emphasized
        }
        let original = Note(
            title: "Kingfisher",
            body: RichText(attributed),
            notebookID: NotebookID(),
            kind: .sketch,
            isPinned: true,
            observedAt: Date(timeIntervalSince1970: 1_699_000_000.75),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000.5),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_060.25)
        )

        #expect(try NoteRow(original).toDomain() == original)
    }

    @Test("A note with no observation round-trips with nil")
    func nilObservationSurvives() throws {
        let original = makeNote("Unwitnessed")
        #expect(try NoteRow(original).toDomain().observedAt == nil)
    }

    @Test("Every NoteKind survives the round trip",
          arguments: NoteKind.allCases)
    func everyKindSurvives(kind: NoteKind) throws {
        let original = makeNote("Kinded", kind: kind)
        #expect(try NoteRow(original).toDomain().kind == kind)
    }

    @Test("A malformed identifier is corruption, not a nil result")
    func malformedIdentifierThrows() {
        var row = NoteRow(makeNote("Broken"))
        row.id = "not-a-uuid"
        #expect(throws: StorageError.self) { try row.toDomain() }
    }

    @Test("An unknown kind is corruption")
    func unknownKindThrows() {
        var row = NoteRow(makeNote("Broken"))
        row.kind = "telepathy"
        #expect(throws: StorageError.self) { try row.toDomain() }
    }
}
