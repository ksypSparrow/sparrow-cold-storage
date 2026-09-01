import Foundation
import GRDB
import SparrowDomain
import StorageContracts
import Testing
@testable import ColdStorage

func tagID(_ label: String) -> TagID {
    TagID(normalizing: label)!
}

/// `SparrowDomain.Tag`, spelled out: Swift Testing has its own `Tag` type for
/// labelling tests, and an unqualified `Tag` is ambiguous in this module.
func makeTag(_ label: String) -> SparrowDomain.Tag {
    SparrowDomain.Tag(label: label)!
}

@Suite("Tag storage")
struct TagStorageTests {
    private func save(_ tag: SparrowDomain.Tag, to storage: StorageSet) async throws {
        try await storage.transactions.write { session in
            try session.tags.upsert(tag)
        }
    }

    @Test("An upserted tag is readable", arguments: StoreKind.allCases)
    func upsertIsVisible(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let tag = makeTag("Field Survey")
        try await save(tag, to: fixture.storage)

        #expect(try await fixture.storage.tags.tag(tag.id)?.label == "Field Survey")
        #expect(try await fixture.storage.tags.allTags().count == 1)
    }

    /// Tags arrive by being *used* — someone types `#wetlands` on a note — so
    /// there is no separate "create tag" step to fail on a duplicate. An
    /// insert that threw would make tagging a second note an error.
    @Test("Upserting the same tag twice is not an error",
          arguments: StoreKind.allCases)
    func upsertIsIdempotent(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let tag = makeTag("Wetlands")

        try await save(tag, to: fixture.storage)
        try await save(tag, to: fixture.storage)
        try await save(tag, to: fixture.storage)

        #expect(try await fixture.storage.tags.allTags().count == 1)
    }

    @Test("Upserting updates the label a person sees",
          arguments: StoreKind.allCases)
    func upsertUpdatesTheLabel(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        try await save(makeTag("field survey"), to: fixture.storage)
        try await save(makeTag("Field Survey"), to: fixture.storage)

        let tags = try await fixture.storage.tags.allTags()
        #expect(tags.count == 1)
        #expect(tags.first?.label == "Field Survey")
    }

    @Test("An unknown tag reads as nil", arguments: StoreKind.allCases)
    func unknownTagIsNil(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        #expect(try await fixture.storage.tags.tag(tagID("absent")) == nil)
    }

    @Test("A tombstoned tag disappears from reads",
          arguments: StoreKind.allCases)
    func tombstonedTagIsHidden(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let tag = makeTag("Transient")
        try await save(tag, to: fixture.storage)

        try await fixture.storage.transactions.write { session in
            try session.tags.markDeleted(tag.id, at: Date())
        }

        #expect(try await fixture.storage.tags.tag(tag.id) == nil)
        #expect(try await fixture.storage.tags.allTags().isEmpty)
    }

    /// Someone typing `#wetlands` again means *the* tag, not a new one that
    /// happens to match.
    @Test("Re-using a tombstoned tag revives it", arguments: StoreKind.allCases)
    func revivingATombstonedTag(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let tag = makeTag("Wetlands")
        try await save(tag, to: fixture.storage)
        try await fixture.storage.transactions.write { session in
            try session.tags.markDeleted(tag.id, at: Date())
        }

        try await save(tag, to: fixture.storage)

        #expect(try await fixture.storage.tags.tag(tag.id)?.label == "Wetlands")
    }

    @Test("Deleting an unknown tag is notFound", arguments: StoreKind.allCases)
    func deletingUnknownTagIsNotFound(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)

        await #expect(throws: StorageError.notFound) {
            try await fixture.storage.transactions.write { session in
                try session.tags.markDeleted(tagID("absent"), at: Date())
            }
        }
    }
}

@Suite("Notes and tags")
struct NoteTagTests {
    private func seed(
        _ storage: StorageSet,
        tags: [SparrowDomain.Tag]
    ) async throws {
        try await storage.transactions.write { session in
            for tag in tags { try session.tags.upsert(tag) }
        }
    }

    private func save(
        _ note: Note,
        to storage: StorageSet
    ) async throws {
        let saved = note
        try await storage.transactions.write { session in
            try session.notes.insert(saved)
            try session.index.index(saved)
        }
    }

    @Test("A note keeps its tags across a read", arguments: StoreKind.allCases)
    func tagsSurviveARead(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let wetlands = makeTag("Wetlands")
        let survey = makeTag("Survey")
        try await seed(fixture.storage, tags: [wetlands, survey])

        var note = makeNote("Kingfisher")
        note.tagIDs = [wetlands.id, survey.id]
        try await save(note, to: fixture.storage)

        let read = try await fixture.storage.notes.note(note.id)
        #expect(read?.tagIDs == [wetlands.id, survey.id])
    }

    /// Tag order is user-visible. A plain join returns rows in whatever order
    /// SQLite finds convenient, and a note whose tags reshuffle between reads
    /// looks like a bug in the view that drew it.
    @Test("Tag order is preserved exactly", arguments: StoreKind.allCases)
    func tagOrderIsPreserved(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        // Deliberately not alphabetical, and not insertion order either.
        let labels = ["Zostera", "Alder", "Marsh", "Bittern"]
        let tags = labels.map(makeTag)
        try await seed(fixture.storage, tags: tags)

        var note = makeNote("Ordered")
        note.tagIDs = tags.map(\.id)
        try await save(note, to: fixture.storage)

        for _ in 0..<3 {
            let read = try await fixture.storage.notes.note(note.id)
            #expect(read?.tagIDs == tags.map(\.id))
        }
    }

    @Test("Re-tagging replaces the whole set", arguments: StoreKind.allCases)
    func retaggingReplaces(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let old = makeTag("Old")
        let new = makeTag("New")
        try await seed(fixture.storage, tags: [old, new])

        var note = makeNote("Retagged")
        note.tagIDs = [old.id]
        try await save(note, to: fixture.storage)

        var edited = note
        edited.tagIDs = [new.id]
        let updated = edited
        try await fixture.storage.transactions.write { session in
            try session.notes.update(updated)
        }

        #expect(try await fixture.storage.notes.note(note.id)?.tagIDs == [new.id])
    }

    /// Deleting a tag must not take the notes with it.
    @Test("Deleting a tag leaves its notes intact",
          arguments: StoreKind.allCases)
    func deletingATagKeepsNotes(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let doomed = makeTag("Doomed")
        try await seed(fixture.storage, tags: [doomed])

        var note = makeNote("Survivor")
        note.tagIDs = [doomed.id]
        try await save(note, to: fixture.storage)

        try await fixture.storage.transactions.write { session in
            try session.tags.markDeleted(doomed.id, at: Date())
        }

        let read = try await fixture.storage.notes.note(note.id)
        #expect(read != nil)
        #expect(read?.plainTitle == "Survivor")
        // The tag is gone from the note's list, because reads join through
        // `tag` and it is tombstoned there.
        #expect(read?.tagIDs.isEmpty == true)
    }

    /// The link survives, so reviving the tag restores it — and V2 merging a
    /// delete-here/keep-there does not have to invent the association again.
    @Test("Reviving a tag restores it on the notes that had it")
    func revivingATagRestoresTheLink() async throws {
        let fixture = try StoreFixture(.onDisk)
        let tag = makeTag("Wetlands")
        try await seed(fixture.storage, tags: [tag])

        var note = makeNote("Tagged")
        note.tagIDs = [tag.id]
        try await save(note, to: fixture.storage)

        try await fixture.storage.transactions.write { session in
            try session.tags.markDeleted(tag.id, at: Date())
        }
        #expect(try await fixture.storage.notes.note(note.id)?.tagIDs.isEmpty == true)

        try await fixture.storage.transactions.write { session in
            try session.tags.upsert(tag)
        }
        #expect(try await fixture.storage.notes.note(note.id)?.tagIDs == [tag.id])
    }

    /// Soft-deleting a note keeps its join rows, so undeleting restores them.
    @Test("Tag links survive a note's soft delete")
    func tagLinksSurviveNoteDeletion() async throws {
        try await withTemporaryDatabase { url in
            let storage = try SQLiteStorage(at: url)
            let tag = makeTag("Kept")
            var draft = makeNote("Deleted")
            draft.tagIDs = [tag.id]
            let note = draft

            try await storage.pool.write { db in
                try TagRow(tag, at: Date()).insert(db)
                try NoteRow(note).insert(db)
                try NoteTags.write(note.tagIDs, for: note.id, in: db)
                try db.execute(
                    sql: "UPDATE note SET deleted_at = ? WHERE id = ?",
                    arguments: [Date().timeIntervalSince1970,
                                note.id.value.uuidString]
                )
            }

            let links = try await storage.pool.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_tag") ?? -1
            }
            #expect(links == 1)
        }
    }
}

@Suite("Filtering by tag")
struct TagFilterTests {
    @Test("Filtering by one tag", arguments: StoreKind.allCases)
    func filterByOneTag(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let wetlands = makeTag("Wetlands")
        try await fixture.storage.transactions.write { session in
            try session.tags.upsert(wetlands)
        }

        var tagged = makeNote("Tagged", at: 0)
        tagged.tagIDs = [wetlands.id]
        let untagged = makeNote("Untagged", at: 60)
        for note in [tagged, untagged] {
            let saved = note
            try await fixture.storage.transactions.write { session in
                try session.notes.insert(saved)
                try session.index.index(saved)
            }
        }

        let found = try await fixture.storage.notes.notes(
            matching: NoteFilter(tagIDs: [wetlands.id]),
            sort: .mostRecent, limit: 10
        )
        #expect(found.map(\.id) == [tagged.id])
    }

    /// ⚠️ `IN (…)` would match a note carrying *any* of the tags;
    /// `NoteFilter.tagIDs` requires *all* of them. The difference is silent —
    /// the query runs and returns too much.
    @Test("Filtering by two tags requires both", arguments: StoreKind.allCases)
    func filterByTwoTagsRequiresBoth(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let wetlands = makeTag("Wetlands")
        let survey = makeTag("Survey")
        try await fixture.storage.transactions.write { session in
            try session.tags.upsert(wetlands)
            try session.tags.upsert(survey)
        }

        var both = makeNote("Both", at: 0)
        both.tagIDs = [wetlands.id, survey.id]
        var one = makeNote("One", at: 60)
        one.tagIDs = [wetlands.id]
        for note in [both, one] {
            let saved = note
            try await fixture.storage.transactions.write { session in
                try session.notes.insert(saved)
                try session.index.index(saved)
            }
        }

        let found = try await fixture.storage.notes.notes(
            matching: NoteFilter(tagIDs: [wetlands.id, survey.id]),
            sort: .mostRecent, limit: 10
        )
        #expect(found.map(\.id) == [both.id])
    }

    @Test("A tombstoned tag matches nothing", arguments: StoreKind.allCases)
    func tombstonedTagMatchesNothing(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let tag = makeTag("Gone")
        try await fixture.storage.transactions.write { session in
            try session.tags.upsert(tag)
        }

        var draft = makeNote("Tagged")
        draft.tagIDs = [tag.id]
        let note = draft
        try await fixture.storage.transactions.write { session in
            try session.notes.insert(note)
            try session.index.index(note)
        }

        try await fixture.storage.transactions.write { session in
            try session.tags.markDeleted(tag.id, at: Date())
        }

        let found = try await fixture.storage.notes.notes(
            matching: NoteFilter(tagIDs: [tag.id]), sort: .mostRecent, limit: 10
        )
        #expect(found.isEmpty)
    }

    @Test("Tags combine with other fields", arguments: StoreKind.allCases)
    func tagsCombineWithOtherFields(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let tag = makeTag("Wetlands")
        try await fixture.storage.transactions.write { session in
            try session.tags.upsert(tag)
        }

        var sketch = makeNote("heron sketch", kind: .sketch, at: 0)
        sketch.tagIDs = [tag.id]
        var voice = makeNote("heron voice", kind: .voice, at: 60)
        voice.tagIDs = [tag.id]
        for note in [sketch, voice] {
            let saved = note
            try await fixture.storage.transactions.write { session in
                try session.notes.insert(saved)
                try session.index.index(saved)
            }
        }

        let found = try await fixture.storage.notes.notes(
            matching: NoteFilter(text: "heron", kinds: [.sketch], tagIDs: [tag.id]),
            sort: .mostRecent, limit: 10
        )
        #expect(found.map(\.id) == [sketch.id])
    }
}
