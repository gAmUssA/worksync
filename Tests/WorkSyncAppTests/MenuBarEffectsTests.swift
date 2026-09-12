import WorkSyncCore
import XCTest
@testable import worksync

/// The boundaries where the model touches the world. Each one is substituted,
/// so the suite is safe to run on a fresh machine: no calendar prompt, no
/// `~/.config/worksync`, no log directory, no timers, no login item.
@MainActor
final class MenuBarEffectsTests: XCTestCase {
    /// The observer hands its callback to the model through a `Task`, the way a
    /// real EventKit notification arrives from another queue. Waiting for a
    /// task enqueued after it is how a test sees the result.
    private func settle() async {
        await Task { @MainActor in }.value
    }

    func testSyncingRunsOnePassAndReportsIt() async throws {
        let (model, recorder, _) = try MenuBarFixture.model(config: MenuBarFixture.twoSources())
        recorder.passOutcome = PassOutcome(disposition: .completed, result: nil, diagnostics: nil)

        model.syncNow()
        XCTAssertTrue(model.isSyncing)
        await model.passTask?.value
        await model.healthTask?.value

        XCTAssertEqual(recorder.passRuns, 1)
        XCTAssertFalse(model.isSyncing)
        XCTAssertEqual(recorder.healthRuns, 1, "a pass is when the environment most plausibly changed")
    }

    func testAPausedModelDoesNotRun() async throws {
        let (model, recorder, _) = try MenuBarFixture.model(config: MenuBarFixture.twoSources())
        model.isPaused = true

        model.syncNow()
        await model.passTask?.value

        XCTAssertEqual(recorder.passRuns, 0)
    }

    func testANotificationIsPostedThroughTheInjectedNotifier() async throws {
        var config = try MenuBarFixture.twoSources()
        config.general.notify = .always
        let (model, recorder, _) = MenuBarFixture.model(config: config)
        recorder.passOutcome = PassOutcome(
            disposition: .failed("target calendar not found"), result: nil, diagnostics: nil
        )

        model.syncNow()
        await model.passTask?.value

        XCTAssertEqual(recorder.notifications.count, 1, "and nothing reached the real notification centre")
    }

    func testHealthIsGatheredThroughTheServiceAndReachesTheIcon() async {
        let (model, recorder, _) = MenuBarFixture.model()
        recorder.health = DoctorReport(findings: [
            DoctorFinding(
                id: "code-signature", title: "Signature", severity: .warning,
                detail: [], remediation: "Re-sign"
            ),
        ])

        model.refreshHealth()
        await model.healthTask?.value

        XCTAssertEqual(model.health?.findings.first?.id, "code-signature")
        XCTAssertEqual(recorder.healthRuns, 1)
    }

    func testCalendarChoicesComeFromTheServiceNotEventKit() async throws {
        let calendars = [
            CalendarRef(id: "1", title: "Personal", accountTitle: "iCloud", allowsModifications: false),
            CalendarRef(id: "2", title: "Work", accountTitle: "Google", allowsModifications: true),
        ]
        let (model, recorder, _) = try await MenuBarFixture.opened(
            config: MenuBarFixture.twoSources(), calendars: calendars
        )

        XCTAssertEqual(recorder.calendarLookups, 1)
        XCTAssertEqual(model.accountChoices, ["Google", "iCloud"])
        XCTAssertEqual(model.selectableCalendarChoices(inAccount: "Google", writableOnly: true), ["Work"])
        XCTAssertTrue(
            model.selectableCalendarChoices(inAccount: "iCloud", writableOnly: true).isEmpty,
            "a read-only calendar is not somewhere blockers can be written"
        )
    }

    // MARK: The change-driven fast path

    func testObservationStartsOnlyAfterAPassHasSucceeded() async throws {
        var config = try MenuBarFixture.twoSources()
        config.general.changeDriven = true
        let observer = FakeChangeObserver()
        let (model, recorder, _) = MenuBarFixture.model(config: config, observer: observer)

        model.reconcileChangeObservation()
        XCTAssertEqual(observer.started, 0, "an observer that cannot fire would report itself as working")

        recorder.passOutcome = PassOutcome(disposition: .completed, result: nil, diagnostics: nil)
        model.syncNow()
        await model.passTask?.value

        XCTAssertEqual(observer.started, 1)
    }

    func testACalendarChangeArmsTheDebounceAndFiresOnePass() async throws {
        var config = try MenuBarFixture.twoSources()
        config.general.changeDriven = true
        config.general.changeDebounceSeconds = 20
        let observer = FakeChangeObserver()
        let (model, recorder, _) = MenuBarFixture.model(config: config, observer: observer)

        model.syncNow()
        await model.passTask?.value
        XCTAssertEqual(observer.started, 1)

        observer.fire()
        observer.fire()
        await settle()
        XCTAssertEqual(
            recorder.scheduledDelays.count, 2,
            "a burst re-arms the one timer rather than adding another"
        )

        recorder.fireScheduledAction()
        await settle()
        await model.passTask?.value
        XCTAssertEqual(recorder.passRuns, 2, "one pass, not two")
    }

    func testTurningTheFastPathOffStopsTheObserverAndTheArmedTimer() async throws {
        var config = try MenuBarFixture.twoSources()
        config.general.changeDriven = true
        let observer = FakeChangeObserver()
        let (model, recorder, _) = MenuBarFixture.model(config: config, observer: observer)

        model.syncNow()
        await model.passTask?.value
        observer.fire()
        await settle()
        XCTAssertNotNil(recorder.scheduledAction)

        config.general.changeDriven = false
        recorder.config = config
        model.reconcileChangeObservation()

        XCTAssertEqual(observer.stopped, 1)
        XCTAssertNil(recorder.scheduledAction, "the one sync they asked not to happen does not happen")
    }

    func testDoctorDestinationsOpenThroughTheService() throws {
        let (model, recorder, _) = try MenuBarFixture.model(config: MenuBarFixture.twoSources())

        model.open(.calendarPrivacySettings)
        model.open(.loginItemSettings)

        XCTAssertEqual(recorder.openedURLs.count, 1, "the privacy pane is a URL")
        XCTAssertTrue(recorder.loginCommands.contains("openSettings"), "login items is not")
    }
}
