import Foundation
import SparrowDomain

/// Reading notebooks.
public protocol NotebookReading: Sendable {
    func notebook(_ id: NotebookID) async throws -> Notebook?
    func allNotebooks() async throws -> [Notebook]

    /// Case-insensitive, because the name arrives from a Shortcut or from
    /// Siri, where nobody types capitals the way the app stored them.
    func notebook(named name: String) async throws -> Notebook?

    /// **Not optional.** Sparrow always has somewhere to put a note — storage
    /// creates one on first run if it must.
    ///
    /// FR-1.1 lets a note be created with no notebook named, and an optional
    /// here would push that decision up into every caller.
    func defaultNotebook() async throws -> Notebook
}
