import Foundation
import SparrowDomain

/// Reading notebooks from outside a transaction.
public protocol NotebookReading: Sendable {
    func notebook(_ id: NotebookID) async throws -> Notebook?
    func allNotebooks() async throws -> [Notebook]

    /// Case-insensitive. The name arrives from a Shortcut or from Siri, where
    /// nobody types capitals the way the app stored them.
    func notebook(named name: String) async throws -> Notebook?

    /// **Not optional.** Sparrow always has somewhere to put a note — storage
    /// creates one on first run if it must.
    func defaultNotebook() async throws -> Notebook
}

/// Reading and writing notebooks inside a transaction.
public protocol NotebookSessionAccess {
    func notebook(_ id: NotebookID) throws -> Notebook?
    func notebook(named name: String) throws -> Notebook?

    /// How many notebooks already sit under `parent`.
    ///
    /// `NotebookDraft` carries no `sortIndex` — a caller creating a notebook
    /// from a Shortcut cannot know how many siblings it will have. This is
    /// what lets storage answer that question for them.
    func siblingCount(under parent: NotebookID?) throws -> Int

    func insert(_ notebook: Notebook) throws
    func update(_ notebook: Notebook) throws
    func markDeleted(_ id: NotebookID, at date: Date) throws
}
