import WorkSyncCore
import XCTest
@testable import worksync

/// Enumerating calendars for the settings pickers. The list is what makes a
/// popup unable to be wrong, so publishing a stale one silently is worse than
/// publishing none: the account and calendar pickers would offer choices from a
/// session the user has already left.
@MainActor
final class CalendarChoicesTests: XCTestCase {
    private let old = [
        CalendarRef(id: "1", title: "Old", accountTitle: "iCloud", allowsModifications: true),
    ]
    private let fresh = [
        CalendarRef(id: "2", title: "Fresh", accountTitle: "Google", allowsModifications: true),
    ]

    func testTheOrdinaryLookupPublishesItsResult() async throws {
        let (model, _, _) = try await MenuBarFixture.opened(
            config: MenuBarFixture.twoSources(), calendars: fresh
        )
        XCTAssertEqual(model.accountChoices, ["Google"])
    }

    /// The regression: a slow first enumeration and a fast second. The second
    /// must win, and the first must not land on top of it afterwards.
    func testASlowLookupCannotOverwriteANewerOne() async throws {
        let gate = CalendarLookupGate()
        let (model, recorder, _) = try MenuBarFixture.model(config: MenuBarFixture.twoSources())
        recorder.calendarGate = gate

        model.openSettings() // first lookup, held open
        await gate.waitForStart(1)
        let first = try XCTUnwrap(model.calendarChoicesTask)

        model.closeSettings()
        model.openSettings() // second lookup
        await gate.waitForStart(2)
        XCTAssertEqual(gate.outstanding, 2, "the first is still running somewhere")
        let second = try XCTUnwrap(model.calendarChoicesTask)

        // The second finishes first and publishes.
        gate.finishNewest(fresh)
        await second.value
        XCTAssertEqual(model.accountChoices, ["Google"])

        // Then the first finishes, late, with last session's calendars. Awaited
        // rather than slept on: the assertion has to follow the stale task
        // actually finishing, or a broken implementation publishes after it.
        gate.finishOldest(old)
        await first.value

        XCTAssertEqual(
            model.accountChoices, ["Google"],
            "the stale lookup must not repopulate the pickers"
        )
    }

    func testClosingSettingsCancelsTheLookupInFlight() async throws {
        let gate = CalendarLookupGate()
        let (model, recorder, _) = try MenuBarFixture.model(config: MenuBarFixture.twoSources())
        recorder.calendarGate = gate

        model.openSettings()
        await gate.waitForStart(1)
        let task = try XCTUnwrap(model.calendarChoicesTask)

        model.closeSettings()
        XCTAssertTrue(task.isCancelled, "the list belongs to the form that asked for it")

        gate.finishOldest(old)
        await task.value
        XCTAssertTrue(
            model.availableCalendars.isEmpty,
            "a cancelled lookup publishes nothing"
        )
    }

    func testReopeningCancelsTheEarlierLookup() async throws {
        let gate = CalendarLookupGate()
        let (model, recorder, _) = try MenuBarFixture.model(config: MenuBarFixture.twoSources())
        recorder.calendarGate = gate

        model.openSettings()
        await gate.waitForStart(1)
        let first = try XCTUnwrap(model.calendarChoicesTask)

        model.openSettings()
        await gate.waitForStart(2)
        XCTAssertTrue(first.isCancelled)
        XCTAssertFalse(try XCTUnwrap(model.calendarChoicesTask).isCancelled)

        let second = try XCTUnwrap(model.calendarChoicesTask)
        gate.finishNewest(fresh)
        await second.value
        XCTAssertEqual(model.accountChoices, ["Google"])

        gate.finishOldest(old)
        await first.value
        XCTAssertEqual(
            model.accountChoices, ["Google"],
            "the cancelled lookup publishes nothing, however late it finishes"
        )
    }
}
