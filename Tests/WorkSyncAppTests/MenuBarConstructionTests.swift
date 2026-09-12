import ServiceManagement
import WorkSyncCore
import XCTest
@testable import worksync

/// Building a model must be inert, and startup must be something a test can
/// drive. Before this, `init` read UserDefaults, loaded two files, created the
/// log directory, asked `SMAppService` for a status and started gathering health
/// — which is why the editing logic was tested through a hand-written copy for
/// eleven rounds instead of through the model that ships.
@MainActor
final class MenuBarConstructionTests: XCTestCase {
    func testConstructingTheModelCallsNoService() {
        // Every service fails the test if called. Reaching the end means the
        // initializer touched nothing outside itself.
        _ = MenuBarModel(
            initialState: MenuBarInitialState(isPaused: false, lastRun: nil, savedSourceIDs: []),
            services: MenuBarFixture.failOnCall()
        )
    }

    func testTheModelStartsFromTheStateItIsGiven() {
        let run = LastRun(
            finishedAt: Date(timeIntervalSince1970: 1_756_000_060),
            succeeded: true,
            summary: "3 blockers"
        )
        let model = MenuBarModel(
            initialState: MenuBarInitialState(
                isPaused: true, lastRun: run, savedSourceIDs: ["personal"]
            ),
            services: MenuBarFixture.failOnCall()
        )

        XCTAssertTrue(model.isPaused)
        XCTAssertEqual(model.lastRun?.summary, "3 blockers")
        XCTAssertEqual(model.savedSourceIDs, ["personal"])
        XCTAssertEqual(model.state, SyncState.paused, "the icon is derived, not read from anywhere")
    }

    func testStartupAsksForTheLoginStatusAndHealth() async {
        let (model, recorder, _) = MenuBarFixture.model()
        recorder.loginStatus = .enabled
        recorder.health = DoctorReport(findings: [
            DoctorFinding(
                id: "calendar-access", title: "Calendar access", severity: .error,
                detail: ["denied"], remediation: "Grant access in System Settings"
            ),
        ])

        model.startInitialRefreshes()
        await model.healthTask?.value

        XCTAssertEqual(model.loginItemStatus, .enabled)
        XCTAssertEqual(recorder.healthRuns, 1)
        XCTAssertEqual(model.health?.findings.count, 1)
        XCTAssertEqual(model.state, SyncState.error, "a health error reaches the menu bar icon")
    }

    func testPausingIsPersistedThroughTheService() {
        let (model, recorder, _) = MenuBarFixture.model()

        model.isPaused = true
        XCTAssertEqual(recorder.pausedWrites, [true])
        XCTAssertEqual(model.state, SyncState.paused)

        model.isPaused = false
        XCTAssertEqual(recorder.pausedWrites, [true, false])
    }

    func testOpeningConfigAndLogGoThroughTheInjectedURLs() throws {
        let (model, recorder, _) = try MenuBarFixture.model(config: MenuBarFixture.twoSources())

        model.openConfig()
        model.openLog()

        XCTAssertEqual(recorder.openedURLs.map(\.path), ["/fixture/config.toml", "/fixture/worksync.log"])
        XCTAssertNil(model.configError, "a config that loads clears the error")
    }

    func testAFailingPassIsReportedAndNotified() async throws {
        let (model, recorder, _) = try MenuBarFixture.model(config: MenuBarFixture.twoSources())
        recorder.config = try MenuBarFixture.twoSources()
        recorder.passOutcome = PassOutcome(
            disposition: .failed("target calendar not found"), result: nil, diagnostics: nil
        )

        model.syncNow()
        await model.passTask?.value
        await model.healthTask?.value

        XCTAssertEqual(recorder.passRuns, 1)
        XCTAssertEqual(model.configError, "target calendar not found")
        XCTAssertFalse(model.isSyncing)
        XCTAssertEqual(model.state, SyncState.error)
    }

    func testTogglingLaunchAtLoginRecordsTheCommand() {
        let (model, recorder, _) = MenuBarFixture.model()
        recorder.loginStatus = .notRegistered

        _ = model.toggleLaunchAtLogin()
        XCTAssertEqual(recorder.loginCommands.first, "register")

        recorder.loginStatus = .enabled
        model.refreshLoginItemStatus()
        _ = model.toggleLaunchAtLogin()
        XCTAssertEqual(recorder.loginCommands.last, "unregister")
    }

    func testApprovalNeededSendsTheUserToSystemSettings() {
        let (model, recorder, _) = MenuBarFixture.model()
        recorder.loginStatus = .requiresApproval

        let message = model.toggleLaunchAtLogin()
        XCTAssertNotNil(message, "the user has something to do, so they are told")
        XCTAssertTrue(recorder.loginCommands.contains("openSettings"))
    }
}
