import Foundation
import SparrowDomain
import StorageContracts
import Testing
@testable import ColdStorage

@Suite("Change events")
struct ChangeEventTests {
    struct Boom: Error {}

    @Test("A committed write publishes the identifiers it touched")
    func commitPublishesTouchedIdentifiers() async throws {
        let storage = try ColdStorage.inMemory()
        var events = storage.observer.changes.makeAsyncIterator()

        let note = makeNote("Observed")
        try await storage.save(note)

        #expect(await events.next() == .notes([note.id]))
    }

    @Test("A rolled-back write publishes nothing")
    func rollbackPublishesNothing() async throws {
        let storage = try ColdStorage.inMemory()
        var events = storage.observer.changes.makeAsyncIterator()

        await #expect(throws: Boom.self) {
            try await storage.transactions.write { session in
                try await session.notes.insert(makeNote("Doomed"))
                throw Boom()
            }
        }

        // The next event must be the *successful* write, not the failed one.
        let survivor = makeNote("Survivor")
        try await storage.save(survivor)
        #expect(await events.next() == .notes([survivor.id]))
    }

    @Test("Two observers both receive the same change")
    func changesAreMulticast() async throws {
        let storage = try ColdStorage.inMemory()
        var first = storage.observer.changes.makeAsyncIterator()
        var second = storage.observer.changes.makeAsyncIterator()

        let note = makeNote("Broadcast")
        try await storage.save(note)

        #expect(await first.next() == .notes([note.id]))
        #expect(await second.next() == .notes([note.id]))
    }
}
