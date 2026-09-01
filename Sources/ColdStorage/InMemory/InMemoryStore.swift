import Foundation
import Synchronization
import SparrowDomain
import StorageContracts

/// The in-memory store: `InMemoryState` behind one mutex.
///
/// The lock is held for the whole of a write, which is what makes the write
/// atomic — and is only possible because a transaction body is synchronous.
final class InMemoryStore: Sendable {
    private let state: Mutex<InMemoryState>
    private let broadcaster: ChangeBroadcaster

    init(broadcaster: ChangeBroadcaster, seededAt date: Date = Date()) {
        self.broadcaster = broadcaster
        self.state = Mutex(InMemoryState(seededAt: date))
    }

    /// Reads, from outside a transaction. Short critical sections.
    func read<T>(_ body: (InMemoryState) throws -> T) rethrows -> T {
        try state.withLock { try body($0) }
    }

    /// Runs `body` as one unit, then publishes what it touched.
    ///
    /// The publish happens **after** the lock is released. A consumer that
    /// reacted by reading the store would otherwise deadlock against the very
    /// write it was told about.
    func transaction<T>(
        _ body: (InMemoryState) throws -> T
    ) throws -> T {
        var touchedNotes: Set<NoteID> = []
        var touchedNotebooks: Set<NotebookID> = []
        var touchedTags: Set<TagID> = []

        let result = try state.withLock { state -> T in
            let snapshot = state.snapshot()
            state.touchedNotes = []
            state.touchedNotebooks = []
            state.touchedTags = []
            do {
                let result = try body(state)
                touchedNotes = state.touchedNotes
                touchedNotebooks = state.touchedNotebooks
                touchedTags = state.touchedTags
                return result
            } catch {
                state.restore(from: snapshot)
                throw error
            }
        }

        if !touchedNotes.isEmpty {
            broadcaster.publish(.notes(Array(touchedNotes)))
        }
        if !touchedNotebooks.isEmpty {
            broadcaster.publish(.notebooks(Array(touchedNotebooks)))
        }
        if !touchedTags.isEmpty {
            broadcaster.publish(.tags(Array(touchedTags)))
        }
        return result
    }
}
