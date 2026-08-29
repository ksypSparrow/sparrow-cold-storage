import Foundation
import StorageContracts

struct InMemorySession: StorageSession {
    let store: InMemoryStore

    var notes: any NoteReading & NoteWriting {
        InMemoryNoteRepository(store: store)
    }

    var index: any SearchIndexing {
        InMemorySearchIndex(store: store)
    }

    var journal: any ChangeJournaling {
        InMemoryJournal(store: store)
    }
}

struct InMemoryTransactionRunner: TransactionRunning {
    let store: InMemoryStore

    func write<T: Sendable>(
        _ body: @Sendable (any StorageSession) async throws -> T
    ) async throws -> T {
        await store.begin()
        do {
            let result = try await body(InMemorySession(store: store))
            await store.commit()
            return result
        } catch {
            await store.rollback()
            throw error
        }
    }
}

struct InMemoryObserver: StorageObserving {
    let broadcaster: ChangeBroadcaster

    var changes: AsyncStream<StoredChange> {
        broadcaster.stream()
    }
}
