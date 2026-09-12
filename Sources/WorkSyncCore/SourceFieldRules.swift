import Foundation

/// What the per-source form must say about four fields, and what it must refuse.
///
/// The rules live here rather than in the view for the reason every rule in this
/// editor does: the menu bar target has no test harness, so anything with a
/// decision in it is unreachable by tests once it is written as SwiftUI.
///
/// Each of these refuses at the field. `ConfigLoader.validate` throws on the
/// same inputs, but that error names a config key and arrives at save time, long
/// after the click that caused it.
public enum SourceFieldRules {
    // MARK: Longest event to mirror

    /// How `max_duration_minutes` reads. `0` is not zero minutes — it is "no
    /// limit", and a bare `0 min` says the opposite of what it means.
    public static func maxDurationDescription(_ minutes: Int) -> String {
        minutes == 0 ? "no limit" : "\(minutes) min"
    }

    /// Why a maximum cannot be saved, or nil.
    ///
    /// A maximum below the minimum is a window nothing can satisfy, so the
    /// source would mirror nothing at all — silently, since every event simply
    /// fails the filter. `ConfigLoader.validate` rejects it too; this is the
    /// same rule, said in front of the field.
    public static func maxDurationProblem(max: Int, min: Int) -> String? {
        guard max > 0, max < min else { return nil }
        return "A longest of \(max) min is below the shortest of \(min) min, so nothing would be mirrored."
    }

    // MARK: Gap between merged events

    /// Whether `coalesce_gap_minutes` does anything. It is the gap below which
    /// two events are merged into one blocker, which only happens while merging
    /// is on.
    public static func coalesceGapApplies(coalesce: Bool) -> Bool {
        coalesce
    }

    public static let coalesceGapUnusedNote = "Only used while “Merge nearby events” is on."

    // MARK: Days to skip

    /// The skipped days in week order, or nil when none are skipped.
    ///
    /// Week order rather than component order, matching what the writer puts in
    /// the file, so the form and the config read the same way round.
    public static func skippedDaysDescription(_ days: Set<Int>) -> String? {
        guard !days.isEmpty else { return nil }
        return Weekday.sortedForWriting(days).compactMap(Weekday.name(for:)).joined(separator: ", ")
    }

    /// Whether `component` can still be turned on.
    ///
    /// The seventh day cannot: skipping every day mirrors nothing, which
    /// `ConfigLoader.validate` rejects. Refused at the switch rather than at
    /// save, so the user never reaches an error for a click the form allowed.
    public static func canSkip(_ component: Int, given days: Set<Int>) -> Bool {
        guard !days.contains(component) else { return true } // turning it off is always allowed
        return days.count < Weekday.componentCount - 1
    }

    public static let lastDayRefusedNote =
        "At least one day has to stay — skipping all seven would mirror nothing."

    /// Why a set of skipped days cannot be saved, or nil. The form refuses the
    /// seventh day, so this is the backstop for a set that arrived another way.
    public static func skippedDaysProblem(_ days: Set<Int>) -> String? {
        days.count >= Weekday.componentCount ? lastDayRefusedNote : nil
    }

    // MARK: Calendar titles a config can name

    /// Titles that name exactly one calendar in `titles`.
    ///
    /// Config stores a calendar by title, and `Resolver.find` refuses a title
    /// that matches more than one — `ResolutionError.ambiguous`, a hard sync
    /// failure. So a title shared by two calendars is not a choice at all,
    /// whichever one the user meant, and a popup that offers it is a popup that
    /// can be wrong.
    ///
    /// The same mistake as keying a source by its id: a name that is not unique
    /// is not identity. The config format keeps storing titles, so the fix is to
    /// stop offering the ones that cannot be resolved rather than to store
    /// something else.
    public static func unambiguousTitles(among titles: [String]) -> [String] {
        var counts: [String: Int] = [:]
        for title in titles {
            counts[title, default: 0] += 1
        }
        return titles.filter { counts[$0] == 1 }
    }

    /// Titles in `titles` that name more than one calendar.
    public static func ambiguousTitles(among titles: [String]) -> Set<String> {
        var counts: [String: Int] = [:]
        for title in titles {
            counts[title, default: 0] += 1
        }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    /// Why a chosen calendar title cannot be used, or nil.
    public static func calendarTitleProblem(_ title: String, among titles: [String]) -> String? {
        guard !title.isEmpty, ambiguousTitles(among: titles).contains(title) else { return nil }
        let count = titles.filter { $0 == title }.count
        return "“\(title)” is the name of \(count) calendars in this account, so the sync cannot tell which one you mean. Rename one of them in Calendar."
    }

    // MARK: Where this source's blockers are written

    /// Empty `target_calendar` means the source writes to `[target].calendar`,
    /// so the popup needs a choice that says so rather than a blank row.
    public static let inheritedTargetCalendar = ""

    public static func targetCalendarDescription(_ title: String, inheriting default: String) -> String {
        title.isEmpty ? "Same as the target calendar (\(`default`))" : title
    }
}
