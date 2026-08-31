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
            try session.notes.insert(note)
            try session.index.index(note)
            try session.journal.record(
                JournalDraft(
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
