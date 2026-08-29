import Foundation
import SparrowDomain
import StorageContracts
import Testing
@testable import ColdStorage

@Suite("Public surface")
struct PublicSurfaceTests {
    /// The invariant the whole storage design rests on. If this ever passes as
    /// a writer, a view can save a note without indexing or journalling it.
    @Test("StorageSet hands out a reader that is not a writer")
    func readerIsNotAWriter() throws {
        let storage = try ColdStorage.inMemory()
        #expect(storage.notes is any NoteReading)
        #expect(!(storage.notes is any NoteWriting))
    }

    @Test("A session, and only a session, exposes a writer")
    func sessionExposesAWriter() async throws {
        let storage = try ColdStorage.inMemory()
        let sawWriter = try await storage.transactions.write { session in
            session.notes is any NoteWriting
        }
        #expect(sawWriter)
    }
}
