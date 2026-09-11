import XCTest
@testable import WorkSyncCore

/// title_matches and title_excludes (SPEC §4.1).
final class TitleFilterTests: XCTestCase {
    /// 2023-11-17 is a Friday in UTC, matching the anchor FiltersTests uses.
    private let friday = Date(timeIntervalSince1970: 1_700_179_200)
    private var utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func source(_ mutate: (inout SourceConfig) -> Void = { _ in }) -> SourceConfig {
        var s = SourceConfig(id: "personal", account: "a", calendar: "c")
        s.minDurationMinutes = 0
        mutate(&s)
        return s
    }

    private func event(titled title: String) -> StoredEvent {
        StoredEvent(
            eventIdentifier: "e", externalIdentifier: "E", occurrenceDate: friday,
            calendarId: "src", title: title, start: friday,
            end: friday.addingTimeInterval(3600),
            isAllDay: false, availability: .busy, isDeclinedByUser: false
        )
    }

    private func keeps(_ title: String, _ config: SourceConfig) -> Bool {
        !SyncPlanner.eligible([event(titled: title)], for: config, calendar: utc).isEmpty
    }

    // MARK: Defaults

    func testEmptyListsMirrorEverything() {
        XCTAssertTrue(keeps("Anything at all", source()))
        XCTAssertTrue(keeps("", source()))
    }

    // MARK: title_matches

    func testMatchesKeepsOnlyListedSubstrings() {
        let config = source { $0.titleMatches = ["Personal Commitment"] }
        XCTAssertTrue(keeps("Personal Commitment", config))
        XCTAssertFalse(keeps("Sprint planning", config))
    }

    func testMatchesIsCaseInsensitive() {
        let config = source { $0.titleMatches = ["personal commitment"] }
        XCTAssertTrue(keeps("PERSONAL COMMITMENT", config))
        XCTAssertTrue(keeps("Personal Commitment", config))
    }

    func testMatchesIsSubstringNotEquality() {
        let config = source { $0.titleMatches = ["commitment"] }
        XCTAssertTrue(keeps("Personal Commitment (via Reclaim)", config))
    }

    func testMatchesAcceptsAnyOfSeveral() {
        let config = source { $0.titleMatches = ["Commitment", "Focus Time"] }
        XCTAssertTrue(keeps("Focus Time", config))
        XCTAssertTrue(keeps("Personal Commitment", config))
        XCTAssertFalse(keeps("Standup", config))
    }

    func testMatchesIsDiacriticInsensitive() {
        let config = source { $0.titleMatches = ["reunion"] }
        XCTAssertTrue(keeps("Réunion d'équipe", config))
    }

    // MARK: title_excludes

    func testExcludesDropsListedSubstrings() {
        let config = source { $0.titleExcludes = ["Lunch"] }
        XCTAssertFalse(keeps("Team Lunch", config))
        XCTAssertTrue(keeps("Team Sync", config))
    }

    func testExcludesWinsOverMatches() {
        let config = source {
            $0.titleMatches = ["Commitment"]
            $0.titleExcludes = ["Tentative"]
        }
        XCTAssertFalse(keeps("Tentative Commitment", config))
        XCTAssertTrue(keeps("Personal Commitment", config))
    }

    // MARK: Privacy invariant

    /// The title gates eligibility but must never reach the blocker.
    func testMatchedTitleIsNeverCopiedToTheBlocker() {
        let config = source {
            $0.titleMatches = ["Personal Commitment"]
            $0.titleTemplate = "Busy"
        }
        let window = Interval(
            start: friday.addingTimeInterval(-3600), end: friday.addingTimeInterval(86400)
        )
        let blocks = SyncPlanner.desiredBlocks(
            source: config,
            targetCalendar: CalendarRef(id: "tgt", title: "Work", accountTitle: "W", allowsModifications: true),
            events: [event(titled: "Personal Commitment: therapy")],
            window: window,
            calendar: utc
        )
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.title, "Busy")
    }

    // MARK: Config parsing

    func testParsesBothKeys() throws {
        let toml = """
        [target]
        account = "W"
        calendar = "Cal"

        [[source]]
        id = "work-a"
        account = "A"
        calendar = "C"
        title_matches = ["Personal Commitment", "Focus Time"]
        title_excludes = ["Declined"]
        """
        let config = try ConfigLoader.parse(toml)
        XCTAssertEqual(config.sources[0].titleMatches, ["Personal Commitment", "Focus Time"])
        XCTAssertEqual(config.sources[0].titleExcludes, ["Declined"])
    }

    func testOmittedKeysDefaultToEmpty() throws {
        let toml = """
        [target]
        account = "W"
        calendar = "Cal"

        [[source]]
        id = "work-a"
        account = "A"
        calendar = "C"
        """
        let config = try ConfigLoader.parse(toml)
        XCTAssertEqual(config.sources[0].titleMatches, [])
        XCTAssertEqual(config.sources[0].titleExcludes, [])
    }

    /// A blank entry would match every title and silently disable the filter.
    func testBlankEntryIsRejected() {
        let toml = """
        [target]
        account = "W"
        calendar = "Cal"

        [[source]]
        id = "work-a"
        account = "A"
        calendar = "C"
        title_matches = ["Personal Commitment", "  "]
        """
        XCTAssertThrowsError(try ConfigLoader.parse(toml))
    }

    func testNonStringEntryIsRejected() {
        let toml = """
        [target]
        account = "W"
        calendar = "Cal"

        [[source]]
        id = "work-a"
        account = "A"
        calendar = "C"
        title_excludes = [42]
        """
        XCTAssertThrowsError(try ConfigLoader.parse(toml))
    }

    // MARK: Write round-trip

    private func rewritten(_ mutate: (inout Config) -> Void) throws -> Config {
        let previous = try ConfigLoader.parse(ExampleConfig.contents)
        var updated = previous
        mutate(&updated)
        let text = ConfigWriter.apply(updated, previous: previous, to: ExampleConfig.contents)
        return try ConfigLoader.parse(text)
    }

    func testFiltersSurviveAWrite() throws {
        let reloaded = try rewritten {
            $0.sources[0].titleMatches = ["Personal Commitment", "Focus Time"]
            $0.sources[0].titleExcludes = ["Declined"]
        }
        XCTAssertEqual(reloaded.sources[0].titleMatches, ["Personal Commitment", "Focus Time"])
        XCTAssertEqual(reloaded.sources[0].titleExcludes, ["Declined"])
    }

    func testClearingAFilterSurvivesAWrite() throws {
        let seeded = try rewritten { $0.sources[0].titleMatches = ["Commitment"] }
        XCTAssertEqual(seeded.sources[0].titleMatches, ["Commitment"])
        let previous = seeded
        var cleared = previous
        cleared.sources[0].titleMatches = []
        let text = ConfigWriter.apply(cleared, previous: previous, to: ExampleConfig.contents)
        XCTAssertEqual(try ConfigLoader.parse(text).sources[0].titleMatches, [])
    }

    /// A value carrying a control character must be escaped on the way out, or
    /// the rendered file is not parseable TOML and the save fails.
    func testFilterWithControlCharactersRoundTrips() throws {
        let reloaded = try rewritten {
            $0.sources[0].titleMatches = ["Focus\nTime", "Tab\tHold", "Quote\"And\\Slash"]
        }
        XCTAssertEqual(
            reloaded.sources[0].titleMatches, ["Focus\nTime", "Tab\tHold", "Quote\"And\\Slash"]
        )
    }

    func testTitleTemplateWithControlCharactersRoundTrips() throws {
        let reloaded = try rewritten { $0.sources[0].titleTemplate = "Busy\nBlock" }
        XCTAssertEqual(reloaded.sources[0].titleTemplate, "Busy\nBlock")
    }
}
