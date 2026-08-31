import Foundation
import SparrowDomain

/// The notebook every store starts with.
///
/// `defaultNotebook()` is not optional — FR-1.1 lets a note be created without
/// naming a notebook, and an optional would push that decision into every
/// caller. So one notebook is seeded when the store is created, and a
/// well-known identifier is what lets both stores agree on which it is.
enum DefaultNotebook {
    /// A fixed identifier, not a fresh `UUID()`. It is the same on every
    /// device, which matters the moment V2 starts merging two of them: a
    /// generated identifier would leave every user with a different "default"
    /// notebook and no way to reconcile them.
    static let identifier = NotebookID(
        UUID(uuidString: "5A88E10B-0000-4000-A000-000000000001")!
    )

    static let name = "Field Notes"

    static func make(at date: Date) -> Notebook {
        Notebook(
            id: identifier,
            name: name,
            parentID: nil,
            colorName: nil,
            sortIndex: 0,
            createdAt: date,
            updatedAt: date
        )
    }
}
