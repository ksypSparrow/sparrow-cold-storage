import Foundation
import SparrowDomain
import StorageContracts
import Testing
@testable import ColdStorage

@Suite("NotebookRow")
struct NotebookRowTests {
    private static let base = Date(timeIntervalSince1970: 1_700_000_000.5)

    @Test("Notebook round-trips through the row and back")
    func roundTripsThroughTheRow() throws {
        let original = Notebook(
            name: "Wetlands",
            parentID: NotebookID(),
            colorName: "riverbank",
            sortIndex: 3,
            createdAt: Self.base,
            updatedAt: Self.base.addingTimeInterval(90)
        )

        let restored = try NotebookRow(original).toDomain()
        #expect(restored == original)
    }

    /// Dates are stored as REAL seconds, so sub-second precision has to
    /// survive. An equality assertion elsewhere would fail intermittently if
    /// it did not.
    @Test("Sub-second timestamps survive the round trip")
    func subSecondPrecisionSurvives() throws {
        let precise = Date(timeIntervalSince1970: 1_700_000_000.123456)
        let original = Notebook(
            name: "Precision",
            createdAt: precise,
            updatedAt: precise
        )

        let restored = try NotebookRow(original).toDomain()
        #expect(restored.createdAt == precise)
    }

    @Test("A top-level notebook round-trips with a nil parent")
    func nilParentSurvives() throws {
        let original = Notebook(name: "Inbox", createdAt: Self.base, updatedAt: Self.base)
        #expect(try NotebookRow(original).toDomain().parentID == nil)
    }

    /// A row whose identifier will not parse is a broken database. Skipping it
    /// silently would hide the corruption behind a notebook that merely fails
    /// to appear.
    @Test("A malformed identifier is corruption, not a nil result")
    func malformedIdentifierThrows() {
        var row = NotebookRow(
            Notebook(name: "Broken", createdAt: Self.base, updatedAt: Self.base)
        )
        row.id = "not-a-uuid"

        #expect(throws: StorageError.self) { try row.toDomain() }
    }

    @Test("A malformed parent identifier is corruption too")
    func malformedParentIdentifierThrows() {
        var row = NotebookRow(
            Notebook(name: "Broken", createdAt: Self.base, updatedAt: Self.base)
        )
        row.parentID = "not-a-uuid"

        #expect(throws: StorageError.self) { try row.toDomain() }
    }
}
