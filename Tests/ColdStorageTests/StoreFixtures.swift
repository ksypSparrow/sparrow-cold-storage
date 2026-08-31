import Foundation
import SparrowDomain
import StorageContracts
import Testing
@testable import ColdStorage

/// The two stores, run against the same assertions.
///
/// The release gate says `.inMemory()` and `.make(at:)` must behave
/// identically. The cheapest way to keep that true is to make it impossible to
/// test one without the other, so the notebook suites are parameterised over
/// this rather than picking a store.
enum StoreKind: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case inMemory
    case onDisk

    var testDescription: String { rawValue }
}

/// A store plus the directory it lives in, removed when the value goes away.
final class StoreFixture {
    let storage: StorageSet
    private let directory: URL?

    init(_ kind: StoreKind) throws {
        switch kind {
        case .inMemory:
            storage = try ColdStorage.inMemory()
            directory = nil
        case .onDisk:
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("sparrow-tests-\(UUID().uuidString)")
            storage = try ColdStorage.make(
                at: directory.appendingPathComponent("sparrow.sqlite")
            )
            self.directory = directory
        }
    }

    deinit {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

/// A temporary database path that cleans up after itself, for tests that need
/// to open the same file twice.
func withTemporaryDatabase<T>(
    _ body: (URL) throws -> T
) rethrows -> T {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("sparrow-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory.appendingPathComponent("sparrow.sqlite"))
}
