import Foundation

/// Judging one entry of a title-filter list while the user is typing it.
///
/// `ConfigLoader.validate` already refuses a blank entry, and for good reason:
/// `""` is a substring of every title, so it silently disables `title_matches`
/// and makes `title_excludes` suppress the whole source. But a settings form
/// that lets the user reach that error has already failed — the message names a
/// config field and arrives at save time, long after the keystroke that caused
/// it. These checks run in front of the field instead, so the affordance that
/// would produce a bad entry is simply not available.
///
/// Lives here rather than in the menu bar target so it can be tested: the app
/// target has no test harness, and this is the part with rules in it.
public enum TitleFilterEntry {
    public enum Check: Equatable {
        /// Nothing typed. Not an error — just nothing to add yet.
        case empty
        /// Whitespace only. `ConfigLoader.validate` would throw on it.
        case blank
        /// Already in the list, under the same matching rules the planner uses.
        case duplicate(String)
        /// Usable, carrying the text as it would be stored.
        case valid(String)
    }

    /// Trailing whitespace in a substring filter is almost always a typo, and
    /// one that costs a match rather than announcing itself.
    public static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// - Parameters:
    ///   - entries: the list `text` would join.
    ///   - index: the row being edited, excluded from the duplicate search so a
    ///     row never collides with itself.
    public static func check(_ text: String, against entries: [String], excluding index: Int? = nil) -> Check {
        let candidate = normalize(text)
        guard !candidate.isEmpty else {
            return text.isEmpty ? .empty : .blank
        }
        for (offset, entry) in entries.enumerated() where offset != index {
            // The planner matches case- and diacritic-insensitively (SPEC §4.1),
            // so two entries differing only that way are one filter written
            // twice, not two filters.
            if normalize(entry).compare(
                candidate, options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame {
                return .duplicate(candidate)
            }
        }
        return .valid(candidate)
    }

    /// What to show the user, or nil when there is nothing to say.
    public static func message(for check: Check) -> String? {
        switch check {
        case .empty, .valid: nil
        case .blank: "An entry cannot be blank — it would match every title."
        case let .duplicate(text): "“\(text)” is already in the list."
        }
    }

    /// `entries` with `text` appended, or nil when it may not be added.
    ///
    /// Returning nil rather than the unchanged list keeps the caller from
    /// reporting a no-op as a successful add.
    public static func adding(_ text: String, to entries: [String]) -> [String]? {
        guard case let .valid(candidate) = check(text, against: entries) else { return nil }
        return entries + [candidate]
    }

    /// Every entry as it should be stored.
    ///
    /// The add field trims, so a row edited in place has to as well. A saved
    /// `" lunch "` passes `ConfigLoader.validate` and then never matches
    /// anything — the planner substring-searches for the padded text, so
    /// "Lunch with Bob" misses and a `title_matches` source quietly stops
    /// producing blockers. Nothing on screen distinguishes that from a filter
    /// that is simply not hitting today.
    ///
    /// A row that trims to nothing stays in the list as an empty one rather
    /// than disappearing: `problem(in:)` then refuses the save, which is the
    /// visible outcome. Dropping it here would be the silent edit this exists
    /// to prevent.
    public static func normalized(_ entries: [String]) -> [String] {
        entries.map(normalize)
    }

    /// The first reason `entries` could not be saved, or nil when it is fine.
    ///
    /// The form's last line of defence: a row edited to blank in place never
    /// passes through `adding`.
    public static func problem(in entries: [String]) -> String? {
        for index in entries.indices {
            switch check(entries[index], against: entries, excluding: index) {
            case .valid:
                continue
            // A stored entry that is empty is as unusable as one that is
            // whitespace; only a draft the user has not started typing is
            // allowed to be empty.
            case .empty, .blank:
                return message(for: .blank)
            case let .duplicate(text):
                return message(for: .duplicate(text))
            }
        }
        return nil
    }
}
