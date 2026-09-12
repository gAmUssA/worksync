import XCTest
@testable import WorkSyncCore

/// The four source fields that had no control until now. Every decision they
/// make is here rather than in the view, because the menu bar target has no test
/// harness — what is written as SwiftUI cannot be run by a test.
final class SourceFieldRulesTests: XCTestCase {
    // MARK: Longest event to mirror

    /// `0` is "no limit". Rendered as `0 min` it says the opposite: that nothing
    /// longer than nothing gets mirrored.
    func testZeroReadsAsNoLimit() {
        XCTAssertEqual(SourceFieldRules.maxDurationDescription(0), "no limit")
    }

    func testAMaximumReadsAsMinutes() {
        XCTAssertEqual(SourceFieldRules.maxDurationDescription(90), "90 min")
    }

    /// `ConfigLoader.validate` rejects this, and the window it describes cannot
    /// be satisfied: every event is either too short or too long.
    func testAMaximumBelowTheMinimumIsRefused() throws {
        let problem = try XCTUnwrap(SourceFieldRules.maxDurationProblem(max: 15, min: 30))
        XCTAssertTrue(problem.contains("15"), problem)
        XCTAssertTrue(problem.contains("30"), problem)
    }

    func testAnOrdinaryWindowIsFine() {
        XCTAssertNil(SourceFieldRules.maxDurationProblem(max: 120, min: 30))
        XCTAssertNil(SourceFieldRules.maxDurationProblem(max: 30, min: 30))
    }

    func testNoLimitIsNeverBelowTheMinimum() {
        // 0 is not a small maximum; it is the absence of one.
        XCTAssertNil(SourceFieldRules.maxDurationProblem(max: 0, min: 30))
    }

    /// Whatever the form refuses, the loader must refuse too — otherwise the
    /// form is guarding a rule that no longer exists.
    func testTheRefusalAgreesWithConfigValidation() throws {
        var config = try ConfigLoader.parse(Self.fixture)
        config.sources[0].minDurationMinutes = 30
        config.sources[0].maxDurationMinutes = 15

        XCTAssertNotNil(SourceFieldRules.maxDurationProblem(max: 15, min: 30))
        XCTAssertThrowsError(try ConfigLoader.validate(config))
    }

    // MARK: Gap between merged events

    func testTheGapOnlyAppliesWhileMergingIsOn() {
        XCTAssertTrue(SourceFieldRules.coalesceGapApplies(coalesce: true))
        XCTAssertFalse(SourceFieldRules.coalesceGapApplies(coalesce: false))
    }

    // MARK: Days to skip

    func testNoSkippedDaysHasNothingToDescribe() {
        XCTAssertNil(SourceFieldRules.skippedDaysDescription([]))
    }

    /// Week order, matching what the writer puts in the file, so the form and
    /// the config read the same way round.
    func testSkippedDaysReadInWeekOrder() {
        XCTAssertEqual(SourceFieldRules.skippedDaysDescription([1, 7]), "sat, sun")
        XCTAssertEqual(SourceFieldRules.skippedDaysDescription([6, 2]), "mon, fri")
    }

    func testADayAlreadySkippedCanAlwaysBeTurnedOff() {
        let sixDays: Set = [2, 3, 4, 5, 6, 7]
        XCTAssertTrue(SourceFieldRules.canSkip(7, given: sixDays), "turning one off must never be blocked")
    }

    /// The seventh switch refuses. Skipping every day mirrors nothing, and the
    /// loader rejects it — better to stop the click than to explain the error it
    /// would have caused.
    func testTheLastRemainingDayCannotBeSkipped() {
        let sixDays: Set = [2, 3, 4, 5, 6, 7] // everything but Sunday
        XCTAssertFalse(SourceFieldRules.canSkip(1, given: sixDays))
    }

    func testAnyDayCanBeSkippedWhileTwoRemain() {
        let fiveDays: Set = [2, 3, 4, 5, 6]
        XCTAssertTrue(SourceFieldRules.canSkip(7, given: fiveDays))
        XCTAssertTrue(SourceFieldRules.canSkip(1, given: fiveDays))
    }

    func testAllSevenDaysIsRefusedAsABackstop() {
        XCTAssertNotNil(SourceFieldRules.skippedDaysProblem([1, 2, 3, 4, 5, 6, 7]))
        XCTAssertNil(SourceFieldRules.skippedDaysProblem([1, 7]))
        XCTAssertNil(SourceFieldRules.skippedDaysProblem([]))
    }

    func testTheAllSevenRefusalAgreesWithConfigValidation() throws {
        var config = try ConfigLoader.parse(Self.fixture)
        config.sources[0].skipWeekdays = Set(1 ... 7)

        XCTAssertNotNil(SourceFieldRules.skippedDaysProblem(config.sources[0].skipWeekdays))
        XCTAssertThrowsError(try ConfigLoader.validate(config))
    }

    func testEveryPickerDayIsAKnownWeekday() {
        XCTAssertEqual(Weekday.pickerOrder.count, Weekday.componentCount)
        XCTAssertEqual(Set(Weekday.pickerOrder).count, Weekday.componentCount, "no day twice")
        for component in Weekday.pickerOrder {
            XCTAssertNotNil(Weekday.name(for: component), "component \(component) has no name")
        }
        XCTAssertEqual(Weekday.name(for: Weekday.pickerOrder[0]), "mon", "the week starts on Monday")
    }

    // MARK: Calendar titles a config can name

    /// Config names a calendar by title, and `Resolver.find` refuses a title
    /// that matches two — so a shared title is not a choice at all, whichever
    /// one the user meant. A popup offering it is a popup that can be wrong,
    /// which is the whole justification for it being a popup (SPEC §11.1).
    func testATitleSharedByTwoCalendarsIsNotOffered() {
        let titles = ["Home", "Work", "Work", "Travel"]
        XCTAssertEqual(SourceFieldRules.unambiguousTitles(among: titles), ["Home", "Travel"])
        XCTAssertEqual(SourceFieldRules.ambiguousTitles(among: titles), ["Work"])
    }

    func testEveryDistinctTitleIsOffered() {
        let titles = ["Home", "Work", "Travel"]
        XCTAssertEqual(SourceFieldRules.unambiguousTitles(among: titles), titles)
        XCTAssertTrue(SourceFieldRules.ambiguousTitles(among: titles).isEmpty)
    }

    func testAChosenAmbiguousTitleIsRefusedWithBothNamesCounted() throws {
        let problem = try XCTUnwrap(
            SourceFieldRules.calendarTitleProblem("Work", among: ["Home", "Work", "Work"])
        )
        XCTAssertTrue(problem.contains("Work"), problem)
        XCTAssertTrue(problem.contains("2 calendars"), problem)
    }

    func testAResolvableTitleIsNotRefused() {
        XCTAssertNil(SourceFieldRules.calendarTitleProblem("Home", among: ["Home", "Work", "Work"]))
    }

    /// Empty is "inherit the target calendar", not a calendar title, so it is
    /// never ambiguous.
    func testTheInheritedChoiceIsNeverRefused() {
        XCTAssertNil(SourceFieldRules.calendarTitleProblem(
            SourceFieldRules.inheritedTargetCalendar, among: ["Work", "Work"]
        ))
    }

    /// The calendar list loads asynchronously; nothing is known to collide
    /// before it arrives, and a spurious error on an empty list would flag every
    /// config on every open.
    func testNothingIsRefusedBeforeTheCalendarListLoads() {
        XCTAssertNil(SourceFieldRules.calendarTitleProblem("Work", among: []))
        XCTAssertTrue(SourceFieldRules.unambiguousTitles(among: []).isEmpty)
    }

    /// What the form refuses is what the resolver refuses: two calendars sharing
    /// a title make the whole sync fail with `ResolutionError.ambiguous`, so a
    /// popup that offers that title is a popup that can be wrong.
    func testTheRefusalAgreesWithTheResolver() throws {
        let calendars = [
            CalendarRef(id: "1", title: "Work", accountTitle: "iCloud", allowsModifications: true),
            CalendarRef(id: "2", title: "Work", accountTitle: "iCloud", allowsModifications: true),
            CalendarRef(id: "3", title: "Home", accountTitle: "iCloud", allowsModifications: true),
        ]
        let config = try ConfigLoader.parse("""
        [target]
        account = "iCloud"
        calendar = "Work"

        [[source]]
        id = "personal"
        account = "iCloud"
        calendar = "Home"
        """)

        XCTAssertNotNil(SourceFieldRules.calendarTitleProblem("Work", among: calendars.map(\.title)))
        let report = Resolver.resolveAll(config: config, calendars: calendars)
        XCTAssertTrue(
            report.problems.contains {
                if case .ambiguous = $0 {
                    true
                } else {
                    false
                }
            },
            "the resolver reports exactly what the form now refuses: \(report.problems)"
        )
    }

    func testCaseVariantTitlesAgreeWithResolverAndPicker() {
        let calendars = [
            CalendarRef(id: "1", title: "Work", accountTitle: "iCloud", allowsModifications: true),
            CalendarRef(id: "2", title: "work", accountTitle: "ICLOUD", allowsModifications: true),
        ]
        let titles = calendars.map(\.title)
        XCTAssertTrue(SourceFieldRules.unambiguousTitles(among: titles).isEmpty)
        XCTAssertEqual(SourceFieldRules.ambiguousTitles(among: titles), ["Work", "work"])
        for title in ["Work", "work", "WORK"] {
            XCTAssertNotNil(SourceFieldRules.calendarTitleProblem(title, among: titles))
            assertResolverAmbiguous(title, calendars: calendars)
        }
        for writableOnly in [false, true] {
            XCTAssertTrue(SourceFieldRules.selectableCalendarChoices(
                in: calendars, account: "icloud", writableOnly: writableOnly
            ).isEmpty)
        }
    }

    func testReadOnlyDuplicateStillMakesWritableChoiceAmbiguous() {
        let calendars = [
            CalendarRef(id: "1", title: "Work", accountTitle: "iCloud", allowsModifications: true),
            CalendarRef(id: "2", title: "Work", accountTitle: "iCloud", allowsModifications: false),
        ]
        XCTAssertTrue(SourceFieldRules.selectableCalendarChoices(
            in: calendars, account: "iCloud", writableOnly: true
        ).isEmpty)
        XCTAssertNotNil(SourceFieldRules.calendarTitleProblem("Work", among: calendars.map(\.title)))
        assertResolverAmbiguous("Work", calendars: calendars)
    }

    func testUniqueChoicesKeepWritabilityAndAccountScope() throws {
        let calendars = [
            CalendarRef(id: "1", title: "Work", accountTitle: "iCloud", allowsModifications: true),
            CalendarRef(id: "2", title: "Home", accountTitle: "ICLOUD", allowsModifications: false),
            CalendarRef(id: "3", title: "Work", accountTitle: "Other", allowsModifications: true),
        ]
        XCTAssertEqual(SourceFieldRules.selectableCalendarChoices(
            in: calendars, account: "icloud", writableOnly: true
        ), ["Work"])
        XCTAssertEqual(SourceFieldRules.selectableCalendarChoices(
            in: calendars, account: "icloud", writableOnly: false
        ), ["Home", "Work"])
        let config = Config(
            general: GeneralConfig(), target: TargetConfig(account: "icloud", calendar: "WORK"),
            sources: [SourceConfig(id: "home", account: "icloud", calendar: "home")]
        )
        XCTAssertNoThrow(try Resolver.resolve(config: config, calendars: calendars))
    }

    private func assertResolverAmbiguous(
        _ title: String,
        calendars: [CalendarRef],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let config = Config(
            general: GeneralConfig(), target: TargetConfig(account: "icloud", calendar: title),
            sources: [SourceConfig(id: "test", account: "icloud", calendar: title)]
        )
        XCTAssertTrue(Resolver.resolveAll(config: config, calendars: calendars).problems.contains(
            .ambiguous(account: "icloud", calendar: title, count: 2)
        ), file: file, line: line)
    }

    // MARK: Where this source's blockers are written

    /// Empty means "wherever `[target]` points", which a blank row in a popup
    /// does not say.
    func testAnEmptyTargetCalendarNamesTheDefault() {
        XCTAssertEqual(
            SourceFieldRules.targetCalendarDescription(
                SourceFieldRules.inheritedTargetCalendar, inheriting: "Calendar"
            ),
            "Same as the target calendar (Calendar)"
        )
    }

    func testAChosenTargetCalendarReadsAsItself() {
        XCTAssertEqual(
            SourceFieldRules.targetCalendarDescription("Travel Blocks", inheriting: "Calendar"),
            "Travel Blocks"
        )
    }

    /// The empty string is the config's own encoding of "inherit", so the
    /// picker's default row and the file agree without a translation step.
    func testInheritingIsTheEmptyStringTheWriterStores() throws {
        var config = try ConfigLoader.parse(Self.fixture)
        config.sources[0].targetCalendar = SourceFieldRules.inheritedTargetCalendar
        XCTAssertNoThrow(try ConfigLoader.validate(config))
        XCTAssertEqual(config.sources[0].targetCalendar, "")
    }

    // MARK: The field rules and the validator are the same rules

    /// They are documented as the same rule, so they must not be two copies of
    /// it. A set with more than seven entries is constructible in memory and
    /// used to be refused at the field and accepted at save.
    func testAnOversizedWeekdaySetIsTreatedIdentically() throws {
        var config = try ConfigLoader.parse(Self.fixture)
        config.sources[0].skipWeekdays = Set(1 ... 9) // more than a week, in memory

        XCTAssertNotNil(SourceFieldRules.skippedDaysProblem(config.sources[0].skipWeekdays))
        XCTAssertThrowsError(try ConfigLoader.validate(config), "validate must refuse what the field refuses")
    }

    func testSixDaysIsAcceptedByBoth() throws {
        var config = try ConfigLoader.parse(Self.fixture)
        config.sources[0].skipWeekdays = [1, 2, 3, 4, 5, 6]

        XCTAssertNil(SourceFieldRules.skippedDaysProblem(config.sources[0].skipWeekdays))
        XCTAssertNoThrow(try ConfigLoader.validate(config))
    }

    func testTheDurationWindowIsAlsoOneRule() throws {
        var config = try ConfigLoader.parse(Self.fixture)
        config.sources[0].minDurationMinutes = 30
        config.sources[0].maxDurationMinutes = 15
        XCTAssertNotNil(SourceFieldRules.maxDurationProblem(max: 15, min: 30))
        XCTAssertThrowsError(try ConfigLoader.validate(config))

        config.sources[0].maxDurationMinutes = 0
        XCTAssertNil(SourceFieldRules.maxDurationProblem(max: 0, min: 30))
        XCTAssertNoThrow(try ConfigLoader.validate(config))
    }

    private static let fixture = """
    [target]
    account = "Work"
    calendar = "Calendar"

    [[source]]
    id = "personal"
    account = "iCloud"
    calendar = "Personal"
    """
}
