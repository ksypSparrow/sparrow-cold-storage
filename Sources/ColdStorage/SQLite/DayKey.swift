import Foundation

/// Which calendar day a note belongs to.
///
/// ⚠️ **Computed once, at write time, and stored.** A day is a calendar
/// question, not an arithmetic one: it depends on the timezone, on daylight
/// saving, and on which day the calendar thinks starts a week. Deriving it on
/// every read would make the same note answer differently after a flight.
///
/// The cost is the opposite hazard: a note written at 23:00 in London keeps
/// that day's key when read in Tokyo. That is the correct trade — the day a
/// person wrote something in is the day they will look for it under.
enum DayKey {
    /// `2026-09-02`, in the current calendar.
    static func string(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
    }
}
