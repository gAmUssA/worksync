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

    /// Judges an entry that is already in the list.
    ///
    /// Identical to `check` except that an empty row counts as blank. The add
    /// field starts empty by definition, so `.empty` is silent there — but a
    /// row the user has deleted every character from is as unusable as one
    /// holding spaces, and `problem(in:)` refuses the save either way. Without
    /// this the user gets a greyed-out Save button and no red caption saying
    /// which row caused it.
    public static func checkRow(_ text: String, against entries: [String], excluding index: Int?) -> Check {
        let result = check(text, against: entries, excluding: index)
        return result == .empty ? .blank : result
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

    // MARK: Editing one source's list, by identity

    /// `sources` with `text` added to one source's list, or nil when nothing
    /// changes — the source is gone, or the text is not addable.
    ///
    /// Resolved by id rather than by an index. A SwiftUI row hands back the
    /// index it was built with, and that index is stale the moment a source is
    /// added, removed, or reordered; subscripting with it traps, which is a
    /// crash rather than a missed edit. Identity does not go stale, and a
    /// source that is no longer there simply yields nil.
    public static func adding(
        _ text: String,
        to list: WritableKeyPath<SourceConfig, [String]>,
        ofSourceWith id: String,
        in sources: [SourceConfig]
    ) -> [SourceConfig]? {
        guard let index = sources.firstIndex(where: { $0.id == id }),
              let entries = adding(text, to: sources[index][keyPath: list]) else { return nil }
        var updated = sources
        updated[index][keyPath: list] = entries
        return updated
    }

    /// Adds one source's draft to that same source's list, and clears the draft
    /// only if the entry landed. Nil when nothing changed.
    ///
    /// Both halves take one source id, in one call, because splitting them is
    /// how a commit for one source came to clear another's: the add took the id
    /// the callback carried and the clear read whatever was selected by then,
    /// so text typed for the source the user was looking at could be appended
    /// to a different one and then wiped.
    ///
    /// A draft belonging to another source reads as empty here, so a callback
    /// whose source no longer applies is ignored rather than retargeted.
    public static func committingDraft(
        _ field: String,
        to list: WritableKeyPath<SourceConfig, [String]>,
        ofSourceWith id: String,
        in sources: [SourceConfig],
        drafts: TitleFilterDrafts
    ) -> (sources: [SourceConfig], drafts: TitleFilterDrafts)? {
        guard let updated = adding(
            drafts.text(field, of: id), to: list, ofSourceWith: id, in: sources
        ) else { return nil }
        var cleared = drafts
        cleared.clear(field, of: id)
        return (updated, cleared)
    }

    /// `sources` with one row removed from a source's list, or nil when the
    /// source is gone or the row is out of range.
    public static func removing(
        at row: Int,
        from list: WritableKeyPath<SourceConfig, [String]>,
        ofSourceWith id: String,
        in sources: [SourceConfig]
    ) -> [SourceConfig]? {
        guard let index = sources.firstIndex(where: { $0.id == id }),
              sources[index][keyPath: list].indices.contains(row) else { return nil }
        var updated = sources
        updated[index][keyPath: list].remove(at: row)
        return updated
    }

    /// `sources` with one row's text replaced, or nil when the source is gone
    /// or the row is out of range.
    ///
    /// The text is stored as typed; `normalized(_:)` trims it at the save
    /// commit point, so a space typed mid-word is not eaten while typing.
    public static func setting(
        _ text: String,
        at row: Int,
        in list: WritableKeyPath<SourceConfig, [String]>,
        ofSourceWith id: String,
        in sources: [SourceConfig]
    ) -> [SourceConfig]? {
        guard let index = sources.firstIndex(where: { $0.id == id }),
              sources[index][keyPath: list].indices.contains(row) else { return nil }
        var updated = sources
        updated[index][keyPath: list][row] = text
        return updated
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
