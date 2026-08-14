import Foundation

/// Maps weekday names in config.toml onto `Calendar` weekday components
/// (1 = Sunday … 7 = Saturday).
public enum Weekday {
    static let byName: [String: Int] = [
        "sun": 1, "sunday": 1,
        "mon": 2, "monday": 2,
        "tue": 3, "tues": 3, "tuesday": 3,
        "wed": 4, "weds": 4, "wednesday": 4,
        "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6,
        "sat": 7, "saturday": 7,
    ]

    public static let allowedNames = "mon | tue | wed | thu | fri | sat | sun (full names accepted)"

    public static func component(from name: String) -> Int? {
        byName[name.lowercased().trimmingCharacters(in: .whitespaces)]
    }

    /// Canonical short names, for writing a config back out.
    static let shortNames: [Int: String] = [
        1: "sun", 2: "mon", 3: "tue", 4: "wed", 5: "thu", 6: "fri", 7: "sat",
    ]

    public static func name(for component: Int) -> String? {
        shortNames[component]
    }

    /// Week order starting Monday, so a written config reads
    /// `["sat", "sun"]` rather than `["sun", "sat"]`.
    public static func sortedForWriting(_ components: Set<Int>) -> [Int] {
        components.sorted { lhs, rhs in
            ((lhs + 5) % 7) < ((rhs + 5) % 7)
        }
    }

    /// True when every moment of the event falls on a skipped weekday.
    ///
    /// Deliberately not "the day it starts on". An event running Saturday
    /// 23:00 to Monday 02:00 covers Monday morning, and dropping it because it
    /// began on a weekend would under-block — the direction that gets you
    /// double-booked. Over-blocking is merely untidy, so the filter only fires
    /// when there is no working minute in the event at all.
    public static func fallsEntirelyOnSkippedDays(
        start: Date,
        end: Date,
        skip: Set<Int>,
        calendar: Calendar
    ) -> Bool {
        guard !skip.isEmpty else { return false }

        var day = calendar.startOfDay(for: start)
        // A zero-length event still occupies the day it starts on.
        let limit = max(end, start.addingTimeInterval(1))

        while day < limit {
            if !skip.contains(calendar.component(.weekday, from: day)) {
                return false
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
            day = next
        }
        return true
    }
}
