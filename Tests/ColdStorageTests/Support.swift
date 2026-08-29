import Foundation
import SparrowDomain
import StorageContracts
@testable import ColdStorage

/// A note with deterministic timestamps, so ordering assertions cannot flake.
func makeNote(
    _ title: String,
    body: String = "",
    at offset: TimeInterval = 0
) -> Note {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    return Note(
        title: title,
        body: body,
        createdAt: base.addingTimeInterval(offset),
        updatedAt: base.addingTimeInterval(offset)
    )
}

extension StorageSet {
    /// The wave-0 write a service performs: save, index and journal together.
    @discardableResult
    func save(_ note: Note) async throws -> Note {
        try await transactions.write { session in
            try await session.notes.insert(note)
            try await session.index.index(note)
            try await session.journal.record(
                JournalEntry(
                    sequence: 1,
                    subject: .note(note.id),
                    operation: .upsert,
                    payload: try JSONEncoder().encode(note),
                    recordedAt: note.updatedAt
                )
            )
            return note
        }
    }
}
