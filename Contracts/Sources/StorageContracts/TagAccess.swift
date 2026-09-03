import Foundation
import SparrowDomain

/// Reading tags from outside a transaction.
public protocol TagReading: Sendable {
    func allTags() async throws -> [Tag]
    func tags(_ ids: [TagID]) async throws -> [Tag]
    func tag(_ id: TagID) async throws -> Tag?
}

/// Reading and writing tags inside a transaction.
public protocol TagSessionAccess {
    func tag(_ id: TagID) throws -> Tag?

    /// Creates the tag if it is new, and leaves it alone if it is not.
    ///
    /// Tags arrive by being *used* — someone types `#wetlands` on a note — so
    /// there is no separate "create tag" step to fail on a duplicate. An
    /// `insert` that threw on a tag two notes share would make tagging a
    /// second note an error.
    func upsert(_ tag: Tag) throws

    /// Tombstones the tag. The notes that carried it are untouched.
    func markDeleted(_ id: TagID, at date: Date) throws
}
