import Foundation
import SparrowDomain
import StorageContracts
import Testing
@testable import ColdStorage

@Suite("Note storage")
struct NoteStorageTests {
    @Test("A saved note is readable outside the transaction")
    func savedNoteIsReadable() async throws {
        let storage = try ColdStorage.inMemory()
        let note = makeNote("Kingfisher", body: "North bank, 40 minutes.")
        try await storage.save(note)

        #expect(try await storage.notes.note(note.id) == note)
        #expect(try await storage.notes.count() == 1)
    }

    @Test("An unknown identifier reads as nil, not as an error")
    func unknownIdentifierIsNil() async throws {
        let storage = try ColdStorage.inMemory()
        #expect(try await storage.notes.note(NoteID()) == nil)
    }

    @Test("Recent notes come back newest first, honouring the limit")
    func recentNotesAreOrdered() async throws {
        let storage = try ColdStorage.inMemory()
        let oldest = makeNote("Oldest", at: 0)
        let middle = makeNote("Middle", at: 60)
        let newest = makeNote("Newest", at: 120)
        for note in [middle, oldest, newest] {
            try await storage.save(note)
        }

        let recent = try await storage.notes.recentNotes(limit: 2)
        #expect(recent.map(\.plainTitleForTest) == ["Newest", "Middle"])
    }

    @Test("Inserting the same identifier twice violates a constraint")
    func duplicateInsertIsRejected() async throws {
        let storage = try ColdStorage.inMemory()
        let note = makeNote("Once")
        try await storage.save(note)

        await #expect(throws: StorageError.self) {
            try await storage.save(note)
        }
        #expect(try await storage.notes.count() == 1)
    }

    @Test("Updating a note that was never inserted is notFound")
    func updateRequiresAnExistingNote() async throws {
        let storage = try ColdStorage.inMemory()
        await #expect(throws: StorageError.notFound) {
            try await storage.transactions.write { session in
                try await session.notes.update(makeNote("Ghost"))
            }
        }
    }
}

extension Note {
    /// 0.1.0 stores plain `String`; this keeps the assertions readable when
    /// the fields become `AttributedString` in 0.4.0.
    var plainTitleForTest: String { title }
}
