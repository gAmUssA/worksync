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

    /// Lets enqueued main-actor work run. The lookup hops actors a few times
    /// before it reaches the gate, so this waits for a condition rather than
    /// guessing how many hops that is.
    private func waitFor(
        _ condition: () -> Bool,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0 ..< 500 {
            if condition() {
                return
            }
            // The lookup runs off the main actor and hops back to it, so
            // yielding alone does not always let it make progress. Polls a
            // condition with a bounded budget rather than sleeping a fixed
            // amount and hoping.
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail(message, file: file, line: line)
    }

    private func settle() async {
        for _ in 0 ..< 10 {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

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
        await waitFor({ gate.started == 1 }, "the first lookup never started")

        model.closeSettings()
        model.openSettings() // second lookup
        await waitFor({ gate.started == 2 }, "the second lookup never started")
        XCTAssertEqual(gate.outstanding, 2, "the first is still running somewhere")

        // The second finishes first and publishes.
        gate.finishNewest(fresh)
        await model.calendarChoicesTask?.value
        XCTAssertEqual(model.accountChoices, ["Google"])

        // Then the first finishes, late, with last session's calendars.
        gate.finishOldest(old)
        await settle()
        await settle()

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
        await waitFor({ gate.started == 1 }, "the lookup never started")
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
        await waitFor({ gate.started == 1 }, "the lookup never started")
        let first = try XCTUnwrap(model.calendarChoicesTask)

        model.openSettings()
        await waitFor({ gate.started == 2 }, "the second lookup never started")
        XCTAssertTrue(first.isCancelled)
        XCTAssertFalse(try XCTUnwrap(model.calendarChoicesTask).isCancelled)

        gate.finishOldest(old)
        gate.finishNewest(fresh)
        await model.calendarChoicesTask?.value
        await settle()

        XCTAssertEqual(model.accountChoices, ["Google"])
    }
}
