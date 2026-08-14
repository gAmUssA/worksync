import XCTest
@testable import WorkSyncCore

final class ConfigTests: XCTestCase {
    /// The SPEC §4 example config, verbatim — comment-dense by design.
    static let exampleConfig = """
    [general]
    window_days = 21            # rolling sync horizon from "now"
    interval_minutes = 10       # menu bar sync timer (and --headless agent interval)
    timezone = "system"         # reserved; v1 always uses system tz
    log_level = "info"          # error | warn | info | debug
    notify = "errors"           # off | errors | always — desktop notifications
                                # after a menu bar pass (§11.2)
    change_driven = false       # opt-in EKEventStoreChanged fast path (§11.2)
    change_debounce_seconds = 20 # coalescing window for change-driven triggers

    [target]
    account = "Confluent Exchange"    # EKSource title of the work account
    calendar = "Calendar"             # calendar title within that account

    # --- Source definitions. Order matters: first matching source wins
    # --- when the same underlying event appears in multiple sources.

    [[source]]
    id = "personal"                    # stable slug, used in event markers
    account = "iCloud"                 # or "Google" — EKSource title
    calendar = "Personal"              # source calendar title
    title_template = "Busy"            # what appears on the work calendar
    target_calendar = ""               # empty = use [target].calendar
    coalesce = true                    # merge overlapping/adjacent events
    coalesce_gap_minutes = 15          # gaps <= this are merged
    min_duration_minutes = 15          # ignore shorter source events
    padding_before_minutes = 0
    padding_after_minutes = 0
    include_all_day = false
    skip_if_work_busy = true           # don't create block if work calendar
                                       # already has a non-worksync event
                                       # overlapping >= 80% of the interval
    availability = "busy"              # busy | free | tentative

    [[source]]
    id = "travel"
    account = "Google"
    calendar = "Travel"                # e.g. TripIt/Flighty-fed calendar
    title_template = "✈️ Flight"
    target_calendar = "Travel Blocks"  # separate work calendar => distinct
                                       # color in Calendar.app/Outlook
    coalesce = false                   # each flight stays a discrete event
    min_duration_minutes = 0
    padding_before_minutes = 120       # airport buffer before departure
    padding_after_minutes = 60
    include_all_day = true             # multi-day trips as all-day blocks
    skip_if_work_busy = false          # flights always get blocked
    availability = "busy"
    """

    func testParsesExampleConfig() throws {
        let config = try ConfigLoader.parse(Self.exampleConfig)
        XCTAssertEqual(config.general.windowDays, 21)
        XCTAssertEqual(config.general.intervalMinutes, 10)
        XCTAssertEqual(config.general.logLevel, .info)
        XCTAssertEqual(config.general.notify, .errors)
        XCTAssertFalse(config.general.changeDriven)
        XCTAssertEqual(config.general.changeDebounceSeconds, 20)
        XCTAssertEqual(config.target.account, "Confluent Exchange")
        XCTAssertEqual(config.target.calendar, "Calendar")

        XCTAssertEqual(config.sources.count, 2)
        // Order preservation is load-bearing (dedup priority).
        XCTAssertEqual(config.sources[0].id, "personal")
        XCTAssertEqual(config.sources[1].id, "travel")

        let personal = config.sources[0]
        XCTAssertTrue(personal.coalesce)
        XCTAssertEqual(personal.coalesceGapMinutes, 15)
        XCTAssertEqual(personal.minDurationMinutes, 15)
        XCTAssertTrue(personal.skipIfWorkBusy)
        XCTAssertEqual(personal.targetCalendar, "")
        XCTAssertEqual(personal.availability, .busy)

        let travel = config.sources[1]
        XCTAssertEqual(travel.titleTemplate, "✈️ Flight")
        XCTAssertEqual(travel.targetCalendar, "Travel Blocks")
        XCTAssertFalse(travel.coalesce)
        XCTAssertEqual(travel.paddingBeforeMinutes, 120)
        XCTAssertEqual(travel.paddingAfterMinutes, 60)
        XCTAssertTrue(travel.includeAllDay)
        XCTAssertFalse(travel.skipIfWorkBusy)
    }

    func testDefaultsApplied() throws {
        let minimal = """
        [target]
        account = "Work"
        calendar = "Calendar"

        [[source]]
        id = "personal"
        account = "iCloud"
        calendar = "Personal"
        """
        let config = try ConfigLoader.parse(minimal)
        XCTAssertEqual(config.general.windowDays, 21)
        XCTAssertEqual(config.general.notify, .errors)
        XCTAssertEqual(config.sources[0].titleTemplate, "Busy")
        XCTAssertFalse(config.sources[0].coalesce)
        XCTAssertEqual(config.sources[0].availability, .busy)
    }

    func testMissingTargetFails() {
        XCTAssertThrowsError(try ConfigLoader
            .parse("[[source]]\nid = \"a\"\naccount = \"x\"\ncalendar = \"y\"")) { error in
                XCTAssertEqual(error as? ConfigError, .missingField("[target]"))
            }
    }

    func testNoSourcesFails() {
        XCTAssertThrowsError(try ConfigLoader.parse("[target]\naccount = \"W\"\ncalendar = \"C\"")) { error in
            XCTAssertEqual(error as? ConfigError, .noSources)
        }
    }

    func testDuplicateSourceIDFails() {
        let toml = """
        [target]
        account = "W"
        calendar = "C"
        [[source]]
        id = "dup"
        account = "a"
        calendar = "b"
        [[source]]
        id = "DUP"
        account = "c"
        calendar = "d"
        """
        XCTAssertThrowsError(try ConfigLoader.parse(toml)) { error in
            guard case .duplicateSourceID = error as? ConfigError else {
                return XCTFail("expected duplicateSourceID, got \(error)")
            }
        }
    }

    func testInvalidEnumFails() {
        let toml = """
        [general]
        log_level = "chatty"
        [target]
        account = "W"
        calendar = "C"
        [[source]]
        id = "a"
        account = "b"
        calendar = "c"
        """
        XCTAssertThrowsError(try ConfigLoader.parse(toml)) { error in
            guard case let .invalidValue(field, value, _) = error as? ConfigError else {
                return XCTFail("expected invalidValue, got \(error)")
            }
            XCTAssertEqual(field, "general.log_level")
            XCTAssertEqual(value, "chatty")
        }
    }

    func testNegativeMinutesFail() {
        let toml = """
        [target]
        account = "W"
        calendar = "C"
        [[source]]
        id = "a"
        account = "b"
        calendar = "c"
        padding_before_minutes = -5
        """
        XCTAssertThrowsError(try ConfigLoader.parse(toml))
    }

    // MARK: Source id is marker-facing, so it is normalized and constrained

    private func configTOML(id: String) -> String {
        """
        [target]
        account = "W"
        calendar = "C"
        [[source]]
        id = "\(id)"
        account = "b"
        calendar = "c"
        """
    }

    func testSourceIDWhitespaceIsTrimmed() throws {
        // Surrounding whitespace is invisible in the file. Storing it verbatim
        // would embed it in every marker, and removing it later would orphan
        // every event written under the padded id.
        let config = try ConfigLoader.parse(configTOML(id: "  personal  "))
        XCTAssertEqual(config.sources[0].id, "personal")
    }

    func testSourceIDWithSlashIsRejected() {
        // "/" separates the fields of worksync://v1/<id>/<key>; an id containing
        // it re-parses as a different (sourceID, key) pair than it was written
        // with, so the event never matches and every pass churns delete+create.
        XCTAssertThrowsError(try ConfigLoader.parse(configTOML(id: "team/personal"))) { error in
            guard case .invalidSourceID = error as? ConfigError else {
                return XCTFail("expected invalidSourceID, got \(error)")
            }
        }
    }

    func testSourceIDWithNewlineIsRejected() {
        // The marker is one line of the event's notes; a break would split it.
        XCTAssertThrowsError(try ConfigLoader.parse(configTOML(id: "per\\nsonal"))) { error in
            guard case .invalidSourceID = error as? ConfigError else {
                return XCTFail("expected invalidSourceID, got \(error)")
            }
        }
    }

    func testWhitespaceOnlySourceIDIsRejected() {
        XCTAssertThrowsError(try ConfigLoader.parse(configTOML(id: "   "))) { error in
            XCTAssertEqual(error as? ConfigError, .emptySourceID)
        }
    }

    func testValidateRejectsUnnormalizedIDFromMemory() {
        // parse() normalizes, but a Config built in memory (the §11.1 editor)
        // must already carry a marker-safe id.
        let config = Config(
            general: GeneralConfig(),
            target: TargetConfig(account: "W", calendar: "C"),
            sources: [SourceConfig(id: "personal ", account: "a", calendar: "b")]
        )
        XCTAssertThrowsError(try ConfigLoader.validate(config)) { error in
            guard case .invalidSourceID = error as? ConfigError else {
                return XCTFail("expected invalidSourceID, got \(error)")
            }
        }
    }

    func testTrimmedIDsStillCollideAsDuplicates() {
        let toml = """
        [target]
        account = "W"
        calendar = "C"
        [[source]]
        id = "personal"
        account = "a"
        calendar = "b"
        [[source]]
        id = " personal "
        account = "c"
        calendar = "d"
        """
        XCTAssertThrowsError(try ConfigLoader.parse(toml)) { error in
            guard case .duplicateSourceID = error as? ConfigError else {
                return XCTFail("expected duplicateSourceID, got \(error)")
            }
        }
    }

    func testGarbageTOMLFails() {
        XCTAssertThrowsError(try ConfigLoader.parse("this is [not toml")) { error in
            guard case .parseFailure = error as? ConfigError else {
                return XCTFail("expected parseFailure, got \(error)")
            }
        }
    }
}
