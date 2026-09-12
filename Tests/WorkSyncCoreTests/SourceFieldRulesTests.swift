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
