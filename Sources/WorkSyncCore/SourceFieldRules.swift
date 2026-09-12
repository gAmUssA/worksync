import Foundation

/// What the per-source form must say about four fields, and what it must refuse.
///
/// The rules live here rather than in the view for the reason every rule in this
/// editor does: the menu bar target has no test harness, so anything with a
/// decision in it is unreachable by tests once it is written as SwiftUI.
///
/// Duration-window and all-seven-days refusals are also enforced by
/// `ConfigLoader.validate`. Coalescing-gap applicability is UI guidance, not a
/// validation error. Calendar ambiguity uses the loaded calendar list before
/// save and is enforced by `Resolver` at sync time, not by config validation.
/// Feedback-loop checks delegate to that same resolver before save.
public enum SourceFieldRules {
    /// Use the sync resolver's own guard, including inherited and cross-source targets.
    /// Other resolution errors retain their existing settings/ sync enforcement paths.
    public static func feedbackLoopProblem(config: Config, calendars: [CalendarRef]) -> String? {
        Resolver.resolveAll(config: config, calendars: calendars).problems.first {
            if case .sourceIsTarget = $0 {
                return true
            }
            return false
        }?.errorDescription
    }

    /// Each choice is checked as a proposed config, so no feedback-loop rule is
    /// duplicated here. Empty is tested as inheritance, not automatically allowed.
    public static func targetCalendarChoices(sourceID: String, config: Config, calendars: [CalendarRef]) -> [String] {
        guard let index = config.sources.firstIndex(where: { $0.id == sourceID }) else { return [] }
        let choices = [""] + selectableCalendarChoices(
            in: calendars,
            account: config.target.account,
            writableOnly: true
        )
        return choices.filter { title in
            var proposed = config
            proposed.sources[index].targetCalendar = title
            return feedbackLoopProblem(config: proposed, calendars: calendars) == nil
        }
    }

    /// Canonical picker tag only; opening a view must not rewrite saved spelling.
    public static func pickerSelection(_ value: String, choices: [String]) -> String {
        choices.first { Resolver.namesMatch($0, value) } ?? value
    }

    public static func accountChoices(in calendars: [CalendarRef]) -> [String] {
        var choices: [String] = []
        for account in calendars.map(\.accountTitle).sorted() {
            if !choices.contains(where: { Resolver.namesMatch($0, account) }) {
                choices.append(account)
            }
        }
        return choices
    }

    /// Prefer a resolvable source seed. If no choice exists, leave an empty draft
    /// for the user to complete rather than choosing a known ambiguous title.
    public static func newSource(id: String, config: Config, calendars: [CalendarRef]) -> SourceConfig {
        for account in accountChoices(in: calendars) {
            for title in selectableCalendarChoices(in: calendars, account: account, writableOnly: false) {
                let source = SourceConfig(id: id, account: account, calendar: title)
                var proposed = config
                proposed.sources.append(source)
                if feedbackLoopProblem(config: proposed, calendars: calendars) == nil {
                    return source
                }
            }
        }
        return SourceConfig(id: id, account: accountChoices(in: calendars).first ?? "", calendar: "")
    }

    // MARK: Longest event to mirror

    /// How `max_duration_minutes` reads. `0` is not zero minutes — it is "no
    /// limit", and a bare `0 min` says the opposite of what it means.
    public static func maxDurationDescription(_ minutes: Int) -> String {
        minutes == 0 ? "no limit" : "\(minutes) min"
    }

    /// Why a maximum cannot be saved, or nil.
    ///
    /// A maximum below the minimum is a window nothing can satisfy, so the
    /// source would mirror no timed events — silently, since each timed event simply
    /// fails the filter. `ConfigLoader.validate` rejects it too; this is the
    /// same rule, said in front of the field.
    public static func maxDurationProblem(max: Int, min: Int) -> String? {
        guard max > 0, max < min else { return nil }
        return "A longest of \(max) min is below the shortest of \(min) min, so no timed event can pass."
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

    /// Calendar choices used by the settings picker.
    public static func selectableCalendarChoices(
        in calendars: [CalendarRef], account: String, writableOnly: Bool
    ) -> [String] {
        let accountCalendars = Resolver.calendars(inAccount: account, among: calendars)
        let titles = accountCalendars.map(\.title)
        // Resolution counts every match before writability can limit the picker.
        return accountCalendars.filter { candidate in
            matchingTitleCount(candidate.title, among: titles) == 1
                && (!writableOnly || candidate.allowsModifications)
        }.map(\.title).sorted()
    }

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
        titles.filter { matchingTitleCount($0, among: titles) == 1 }
    }

    /// Original spellings of titles that match more than one calendar under
    /// `Resolver`'s comparison. This set is for display, not exact membership checks.
    public static func ambiguousTitles(among titles: [String]) -> Set<String> {
        Set(titles.filter { matchingTitleCount($0, among: titles) > 1 })
    }

    private static func matchingTitleCount(_ title: String, among titles: [String]) -> Int {
        titles.filter { Resolver.namesMatch($0, title) }.count
    }

    /// Why a chosen calendar title is ambiguous, or nil. Supply every calendar
    /// title in the resolver's account scope, including read-only calendars.
    /// Missing calendars and other resolution failures remain resolver checks.
    public static func calendarTitleProblem(_ title: String, among titles: [String]) -> String? {
        guard !title.isEmpty else { return nil }
        let count = matchingTitleCount(title, among: titles)
        guard count > 1 else { return nil }
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
