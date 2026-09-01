import Foundation

/// The in-memory store's search, kept deliberately in step with FTS5.
///
/// ⚠️ **This exists because the two stores must answer identically.** The naive
/// substring matcher this replaces passed every test that only ran against it,
/// and failed the moment the same suites ran against SQLite: no diacritic
/// folding, no term ANDing, no prefix matching. A test double that is weaker
/// than the real thing is worse than no double at all — it makes the service
/// layer above look correct.
///
/// The behaviour mirrored here is FTS5 with
/// `tokenize = 'unicode61 remove_diacritics 2'` and a `"term"*` query per word.
enum SearchText {
    /// What `remove_diacritics 2` does: strip accents, ignore case.
    static func fold(_ text: String) -> String {
        text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: nil
        )
    }

    /// The words a query asks for, folded the same way the index was.
    static func terms(in text: String) -> [String] {
        fold(text)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Every term must prefix some word — the AND of `"term"*` queries.
    static func matches(_ terms: [String], in haystack: String) -> Bool {
        let words = haystack.split(
            whereSeparator: { !$0.isLetter && !$0.isNumber }
        )
        return terms.allSatisfy { term in
            words.contains { $0.hasPrefix(term) }
        }
    }
}
