import XCTest
@testable import WorkSyncCore

/// max_duration_minutes and skip_weekdays (SPEC §4.1).
final class FiltersTests: XCTestCase {
    /// 2023-11-17 is a Friday in UTC; anchoring everything to it makes the
    /// weekday cases readable.
    private let friday = Date(timeIntervalSince1970: 1_700_179_200) // Fri 2023-11-17 00:00 UTC
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

    /// Hours offset from Friday 00:00 UTC.
    private func event(fromHours: Double, hours: Double, allDay: Bool = false) -> StoredEvent {
        let start = friday.addingTimeInterval(fromHours * 3600)
        return StoredEvent(
            eventIdentifier: "e", externalIdentifier: "E", occurrenceDate: start,
            calendarId: "src", title: "Thing", start: start,
            end: start.addingTimeInterval(hours * 3600),
            isAllDay: allDay, availability: .busy, isDeclinedByUser: false
        )
    }

    private func keeps(_ event: StoredEvent, _ config: SourceConfig) -> Bool {
        !SyncPlanner.eligible([event], for: config, calendar: utc).isEmpty
    }

    // MARK: max_duration_minutes

    func testUnlimitedByDefault() {
        XCTAssertTrue(keeps(event(fromHours: 9, hours: 12), source()))
    }

    func testDropsEventsOverTheMaximum() {
        let src = source { $0.maxDurationMinutes = 240 }
        XCTAssertFalse(keeps(event(fromHours: 9, hours: 5), src))
    }

    func testKeepsEventsExactlyAtTheMaximum() {
        let src = source { $0.maxDurationMinutes = 240 }
        XCTAssertTrue(keeps(event(fromHours: 9, hours: 4), src), "the limit is inclusive")
    }

    func testMaximumIgnoresAllDayEvents() {
        // All-day is gated by include_all_day; every all-day event would
        // otherwise exceed any sane maximum.
        let src = source {
            $0.maxDurationMinutes = 240
            $0.includeAllDay = true
        }
        XCTAssertTrue(keeps(event(fromHours: 0, hours: 24, allDay: true), src))
    }

    func testMaximumIsMeasuredBeforePadding() {
        // A 3h flight with 3h of padding is 6h wall-clock but must still pass a
        // 4h limit: padding is unrelated config and must not decide eligibility.
        let src = source {
            $0.maxDurationMinutes = 240
            $0.paddingBeforeMinutes = 120
            $0.paddingAfterMinutes = 60
        }
        XCTAssertTrue(keeps(event(fromHours: 9, hours: 3), src))
    }

    // MARK: skip_weekdays

    private let weekendOff = { (s: inout SourceConfig) in s.skipWeekdays = [7, 1] } // Sat, Sun

    func testSkipsAnEventFullyInsideASkippedDay() {
        XCTAssertFalse(keeps(event(fromHours: 34, hours: 2), source(weekendOff)), "Sat 10:00–12:00")
    }

    func testKeepsAnEventOnAWorkingDay() {
        XCTAssertTrue(keeps(event(fromHours: 9, hours: 1), source(weekendOff)), "Fri 09:00–10:00")
    }

    func testKeepsAnEventStartingFridayAndEndingSaturday() {
        // Starts on a working day: kept under either rule.
        XCTAssertTrue(keeps(event(fromHours: 22, hours: 3), source(weekendOff)), "Fri 22:00–Sat 01:00")
    }

    func testKeepsAnEventThatStartsSaturdayButRunsIntoMonday() {
        // The case the start-day rule gets wrong: this covers Monday morning,
        // and dropping it would under-block.
        XCTAssertTrue(
            keeps(event(fromHours: 47, hours: 27), source(weekendOff)),
            "Sat 23:00–Mon 02:00 must survive: it contains working time"
        )
    }

    func testSkipsAnEventSpanningOnlySaturdayAndSunday() {
        XCTAssertFalse(keeps(event(fromHours: 34, hours: 24), source(weekendOff)), "Sat 10:00–Sun 10:00")
    }

    func testSkipsAnAllDayEventOnASkippedDay() {
        var src = source(weekendOff)
        src.includeAllDay = true
        XCTAssertFalse(keeps(event(fromHours: 24, hours: 24, allDay: true), src), "all-day Saturday")
    }

    func testEmptySkipListSkipsNothing() {
        XCTAssertTrue(keeps(event(fromHours: 34, hours: 2), source()))
    }

    // MARK: Config parsing and validation

    private func parse(_ sourceBody: String) throws -> SourceConfig {
        try ConfigLoader.parse("""
        [target]
        account = "W"
        calendar = "C"
        [[source]]
        id = "personal"
        account = "a"
        calendar = "c"
        \(sourceBody)
        """).sources[0]
    }

    func testParsesWeekdayNames() throws {
        let source = try parse(#"skip_weekdays = ["sat", "Sunday", "MON"]"#)
        XCTAssertEqual(source.skipWeekdays, [7, 1, 2])
    }

    func testRejectsUnknownWeekdayName() {
        XCTAssertThrowsError(try parse(#"skip_weekdays = ["caturday"]"#)) { error in
            guard case let .invalidValue(_, value, _) = error as? ConfigError else {
                return XCTFail("expected invalidValue, got \(error)")
            }
            XCTAssertEqual(value, "caturday")
        }
    }

    func testRejectsSkippingEveryDay() {
        XCTAssertThrowsError(
            try parse(#"skip_weekdays = ["mon","tue","wed","thu","fri","sat","sun"]"#)
        ) { error in
            guard case .invalidValue = error as? ConfigError else {
                return XCTFail("expected invalidValue, got \(error)")
            }
        }
    }

    func testRejectsMaxBelowMin() {
        // An unsatisfiable window would silently mirror nothing.
        XCTAssertThrowsError(try parse("min_duration_minutes = 60\nmax_duration_minutes = 30")) { error in
            guard case .invalidValue = error as? ConfigError else {
                return XCTFail("expected invalidValue, got \(error)")
            }
        }
    }

    func testAllowsZeroMaxWithNonZeroMin() {
        let source = try? parse("min_duration_minutes = 60\nmax_duration_minutes = 0")
        XCTAssertEqual(source?.maxDurationMinutes, 0, "0 is unlimited, not a bound below the minimum")
    }
}
