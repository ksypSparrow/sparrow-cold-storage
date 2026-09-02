import Foundation
import GRDB
import SparrowDomain
import StorageContracts
import Testing
@testable import ColdStorage

@Suite("Daily notes")
struct DailyNoteTests {
    /// Noon, so a test never sits within a few hours of a day boundary and
    /// starts failing depending on when it runs.
    private static let noon = Date(timeIntervalSince1970: 1_756_814_400)

    private func daily(
        _ title: String,
        on date: Date,
        observedAt: Date? = nil
    ) -> Note {
        Note(
            title: RichText(plain: title),
            notebookID: DefaultNotebook.identifier,
            kind: .daily,
            observedAt: observedAt,
            createdAt: date,
            updatedAt: date
        )
    }

    private func save(_ note: Note, to storage: StorageSet) async throws {
        try await storage.transactions.write { session in
            try session.notes.insert(note)
            try session.index.index(note)
        }
    }

    @Test("A daily note is found by its day", arguments: StoreKind.allCases)
    func dailyNoteIsFound(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let note = daily("Today", on: Self.noon)
        try await save(note, to: fixture.storage)

        #expect(try await fixture.storage.notes.dailyNote(on: Self.noon)?.id == note.id)
    }

    @Test("A day with no entry reads as nil", arguments: StoreKind.allCases)
    func emptyDayIsNil(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        #expect(try await fixture.storage.notes.dailyNote(on: Self.noon) == nil)
    }

    @Test("Any moment in the day finds the same entry",
          arguments: StoreKind.allCases)
    func anyMomentInTheDayMatches(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let note = daily("Today", on: Self.noon)
        try await save(note, to: fixture.storage)

        // Early morning and late evening of the same calendar day.
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Self.noon)
        let nearlyMidnight = start.addingTimeInterval(23 * 3_600 + 59 * 60)

        #expect(try await fixture.storage.notes.dailyNote(on: start)?.id == note.id)
        #expect(try await fixture.storage.notes.dailyNote(on: nearlyMidnight)?.id == note.id)
    }

    /// A 24-hour window from an epoch second is not a day. Only the calendar
    /// knows where the boundary is, and it moves with the timezone.
    @Test("Day boundaries follow the calendar, not a 24-hour offset",
          arguments: StoreKind.allCases)
    func boundariesFollowTheCalendar(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Self.noon)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let note = daily("Today", on: today.addingTimeInterval(3_600))
        try await save(note, to: fixture.storage)

        #expect(try await fixture.storage.notes.dailyNote(on: today)?.id == note.id)
        #expect(try await fixture.storage.notes.dailyNote(on: tomorrow) == nil)
    }

    /// A daily entry written after midnight *about yesterday* belongs to
    /// yesterday. `happenedAt` already encodes that, so the day key uses it.
    @Test("observedAt decides the day, when there is one",
          arguments: StoreKind.allCases)
    func observedAtDecidesTheDay(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Self.noon)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        // Written at 00:30 today, about yesterday afternoon.
        let note = daily(
            "Late write-up",
            on: today.addingTimeInterval(1_800),
            observedAt: yesterday.addingTimeInterval(15 * 3_600)
        )
        try await save(note, to: fixture.storage)

        #expect(try await fixture.storage.notes.dailyNote(on: yesterday)?.id == note.id)
        #expect(try await fixture.storage.notes.dailyNote(on: today) == nil)
    }

    // MARK: The constraint

    /// The database is the thing that cannot be raced. The service guards this
    /// too, in kit 0.8.0 — both, in that order.
    @Test("Two daily notes on the same day are refused",
          arguments: StoreKind.allCases)
    func twoDailyNotesClash(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        try await save(daily("First", on: Self.noon), to: fixture.storage)

        await #expect(throws: (any Error).self) {
            try await self.save(
                self.daily("Second", on: Self.noon.addingTimeInterval(3_600)),
                to: fixture.storage
            )
        }
        #expect(try await fixture.storage.notes.count() == 1)
    }

    @Test("Daily notes on different days are fine",
          arguments: StoreKind.allCases)
    func differentDaysAreFine(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Self.noon).addingTimeInterval(3_600)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        try await save(daily("Today", on: today), to: fixture.storage)
        try await save(daily("Tomorrow", on: tomorrow), to: fixture.storage)

        #expect(try await fixture.storage.notes.count() == 2)
    }

    /// Deleting today's entry must not prevent writing another one, which is
    /// why the index excludes tombstones.
    @Test("A deleted daily note frees its day", arguments: StoreKind.allCases)
    func deletingFreesTheDay(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let first = daily("First", on: Self.noon)
        try await save(first, to: fixture.storage)

        try await fixture.storage.transactions.write { session in
            try session.notes.markDeleted(first.id, at: Date())
            try session.index.remove(first.id)
        }
        try await save(daily("Second", on: Self.noon), to: fixture.storage)

        #expect(try await fixture.storage.notes.dailyNote(on: Self.noon)?.plainTitle == "Second")
    }

    @Test("Ordinary notes are not constrained", arguments: StoreKind.allCases)
    func ordinaryNotesAreUnconstrained(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)

        for index in 0..<3 {
            try await save(
                makeNote("Observation \(index)", at: TimeInterval(index)),
                to: fixture.storage
            )
        }
        #expect(try await fixture.storage.notes.count() == 3)
    }

    @Test("An ordinary note is never returned as a daily note",
          arguments: StoreKind.allCases)
    func ordinaryNotesAreNotDaily(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        try await save(makeNote("Ordinary", at: 0), to: fixture.storage)

        #expect(try await fixture.storage.notes.dailyNote(on: Self.noon) == nil)
    }
}

@Suite("Migration v5")
struct DailyMigrationTests {
    @Test("v5 adds the day column and the partial unique index")
    func v5AddsColumnAndIndex() throws {
        try withTemporaryDatabase { url in
            let storage = try SQLiteStorage(at: url)

            let (columns, indexes) = try storage.pool.read { db in
                try (
                    db.columns(in: "note").map(\.name),
                    db.indexes(on: "note").map(\.name)
                )
            }
            #expect(columns.contains("day"))
            #expect(indexes.contains("note_daily_unique"))
        }
    }

    /// The migration backfills `day` before building the index, so a database
    /// that already had daily notes cannot fail to migrate.
    @Test("v5 applies cleanly to a database with existing daily notes")
    func v5BackfillsExistingDailyNotes() async throws {
        try await withTemporaryDatabase { url in
            let storage = try SQLiteStorage(at: url)
            let note = Note(
                title: "Pre-existing",
                notebookID: DefaultNotebook.identifier,
                kind: .daily,
                createdAt: Date(timeIntervalSince1970: 1_756_814_400),
                updatedAt: Date(timeIntervalSince1970: 1_756_814_400)
            )

            // Simulate a genuinely pre-v5 database: the row exists, and the
            // column and index do not. Removing only the migration record
            // would leave the column behind, and v5 would fail on its own
            // ALTER — which is a flaw in the fake, not in the migration.
            try await storage.pool.write { db in
                try NoteRow(note).insert(db)
                try db.execute(sql: "DROP INDEX note_daily_unique")
                try db.execute(sql: "ALTER TABLE note DROP COLUMN day")
                try db.execute(
                    sql: """
                        DELETE FROM grdb_migrations
                         WHERE identifier = 'v5_daily_unique'
                        """
                )
            }

            let reopened = try SQLiteStorage(at: url)
            let day = try await reopened.pool.read { db in
                try String.fetchOne(db, sql: "SELECT day FROM note LIMIT 1")
            }
            #expect(day == "2025-09-02")
        }
    }
}
