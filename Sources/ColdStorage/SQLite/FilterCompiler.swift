import Foundation
internal import GRDB
import SparrowDomain
import StorageContracts

/// Turns a `NoteFilter` into bound SQL.
///
/// ⚠️ **Never string-interpolate a value into the SQL.** Every value becomes a
/// `?` with an argument beside it. A note title is arbitrary text a person
/// typed, and a filter is built from what a Shortcut passed in — neither is
/// trustworthy, and a single interpolated quote is the whole class of bug.
enum FilterCompiler {
    struct Predicate {
        /// Conditions joined with AND. Always includes the tombstone check.
        let sql: String
        let arguments: StatementArguments
    }

    /// The structural fields, compiled. `text` is not here — it is answered by
    /// FTS5, which `SQLiteNoteRepository` joins separately.
    static func predicate(for filter: NoteFilter) -> Predicate {
        var conditions: [String] = ["n.deleted_at IS NULL"]
        var arguments: [any DatabaseValueConvertible] = []

        if let notebookID = filter.notebookID {
            conditions.append("n.notebook_id = ?")
            arguments.append(notebookID.value.uuidString)
        }

        // ⚠️ An **empty** set means *any kind* — so it compiles to no clause
        // at all. The natural translation, `IN ()`, is both invalid SQLite and
        // the opposite of what the filter means.
        if !filter.kinds.isEmpty {
            // Sorted so the same filter always produces the same SQL, which
            // keeps SQLite's statement cache useful.
            let kinds = filter.kinds.map(\.rawValue).sorted()
            let placeholders = Array(repeating: "?", count: kinds.count)
                .joined(separator: ", ")
            conditions.append("n.kind IN (\(placeholders))")
            arguments.append(contentsOf: kinds)
        }

        // ⚠️ One EXISTS per tag, not `tag_id IN (…)`.
        //
        // `IN` would match a note carrying *any* of them; `NoteFilter.tagIDs`
        // requires *all* of them. The difference is silent — the query runs
        // and returns too much — so it is worth the extra subquery.
        for tagID in filter.tagIDs.map(\.slug).sorted() {
            conditions.append("""
                EXISTS (
                    SELECT 1 FROM note_tag nt
                      JOIN tag t ON t.id = nt.tag_id
                     WHERE nt.note_id = n.id
                       AND nt.tag_id = ?
                       AND t.deleted_at IS NULL
                )
                """)
            arguments.append(tagID)
        }

        if let isPinned = filter.isPinned {
            conditions.append("n.is_pinned = ?")
            arguments.append(isPinned)
        }

        if let created = filter.createdWithin {
            conditions.append("n.created_at >= ? AND n.created_at <= ?")
            arguments.append(created.start.timeIntervalSince1970)
            arguments.append(created.end.timeIntervalSince1970)
        }

        if let updated = filter.updatedWithin {
            conditions.append("n.updated_at >= ? AND n.updated_at <= ?")
            arguments.append(updated.start.timeIntervalSince1970)
            arguments.append(updated.end.timeIntervalSince1970)
        }

        return Predicate(
            sql: conditions.joined(separator: " AND "),
            arguments: StatementArguments(arguments)
        )
    }

    /// The ORDER BY, matching `NoteSort.orders(_:before:)` exactly — including
    /// the identifier tiebreak, without which two notes saved in the same
    /// second would reshuffle between reads.
    static func orderClause(for sort: NoteSort) -> String {
        let direction = sort.order == .ascending ? "ASC" : "DESC"
        let column = switch sort.field {
        case .updated: "n.updated_at"
        case .created: "n.created_at"
        // `Note.happenedAt`: the observation, falling back to creation.
        case .observed: "COALESCE(n.observed_at, n.created_at)"
        case .title: "n.title_plain COLLATE NOCASE"
        // ⚠️ Reachable only once `SparrowDomain` ships as a resilient binary:
        // a field added there is *unknown* here until this file is updated.
        // The fallback is deliberately the same column `NoteSort.Field.updated`
        // maps to, so an unhandled field degrades to a defined order rather
        // than an arbitrary one — but it will still disagree with
        // `NoteSort.orders(_:before:)`, which is the parity bug this codebase
        // has hit three times. Adding a case to that enum means editing here.
        @unknown default: "n.updated_at"
        }
        return "ORDER BY \(column) \(direction), n.id \(direction)"
    }
}
