import WorkSyncCore
import XCTest
@testable import worksync

/// The setup state, derived from doctor's findings rather than stored
/// (`worksync-n2bv`, `worksync-8vdh`).
///
/// The milestone rests on there being no completion flag: a stored "done"
/// cannot un-set itself when calendar access is revoked six months later, so
/// it forces a second answer to "is this set up?" that drifts from doctor's.
@MainActor
final class SetupStateTests: XCTestCase {
    private func report(_ findings: [DoctorFinding]) -> DoctorReport {
        DoctorReport(findings: findings)
    }

    private func allGreen() -> [DoctorFinding] {
        SetupPrerequisites.ordered.map { DoctorFinding.ok(id: $0, $0) }
    }

    private func accessDenied() -> [DoctorFinding] {
        var findings = allGreen()
        findings[0] = DoctorFinding(
            id: "calendar-access", title: "No calendar access", severity: .error,
            remediation: "Grant access in System Settings", exitCode: 2
        )
        return findings
    }

    private func model(health: DoctorReport?) async -> (MenuBarModel, MenuBarRecorder) {
        let (model, recorder, _) = MenuBarFixture.model(config: MenuBarFixture.emptyConfig)
        if let health {
            recorder.health = health
            model.refreshHealth()
            await model.healthTask?.value
        }
        return (model, recorder)
    }

    // MARK: The icon

    func testAnUnconfiguredMachineNeedsSetupRatherThanShowingAnError() async {
        let (model, _) = await model(health: report(accessDenied()))

        XCTAssertEqual(
            model.state, .needsSetup,
            "a fresh install is not a failure; the red badge would say something broke"
        )
        XCTAssertNotEqual(model.state.symbolName, SyncState.error.symbolName)
    }

    func testAConfiguredMachineWithAFailureStillShowsTheError() async {
        var findings = allGreen()
        findings.append(
            DoctorFinding(
                id: "log-size", title: "Log is enormous", severity: .error,
                remediation: "rotate it", exitCode: 1
            )
        )
        let (model, _) = await model(health: report(findings))

        XCTAssertEqual(
            model.state, .error,
            "every prerequisite is met, so this is a working install that broke"
        )
    }

    func testRevokedAccessReturnsToNeedsSetupWithNoSecondCodePath() async {
        let (model, recorder) = await model(health: report(allGreen()))
        XCTAssertEqual(model.state, .idle)

        recorder.health = report(accessDenied())
        model.refreshHealth()
        await model.healthTask?.value

        XCTAssertEqual(
            model.state, .needsSetup,
            "the same derivation that let setup finish takes it back"
        )
    }

    func testPausedOutranksNeedsSetup() async {
        let (model, _) = await model(health: report(accessDenied()))
        model.isPaused = true

        XCTAssertEqual(model.state, .paused, "an explicit user action outranks a derived state")
    }

    func testNothingIsClaimedBeforeTheFirstHealthRun() async {
        let (model, _) = await model(health: nil)

        XCTAssertEqual(
            model.state, .idle,
            "with no report there is nothing to derive from; claiming setup would flash a "
                + "badge at every launch before the first check finishes"
        )
    }

    func testTheNeedsSetupIconIsItsOwn() {
        let symbols = [SyncState.idle, .syncing, .error, .paused, .needsSetup].map(\.symbolName)
        XCTAssertEqual(Set(symbols).count, symbols.count, "each state has to be distinguishable")
        XCTAssertFalse(SyncState.needsSetup.accessibilityLabel.isEmpty)
    }

    // MARK: Leaving settings re-derives the screen

    func testClosingSettingsLandsOnSetupWhenABlockerAppeared() async {
        let (model, recorder) = await model(health: report(allGreen()))
        model.openSettings()
        XCTAssertEqual(model.screen, .settings)

        recorder.health = report(accessDenied())
        model.refreshHealth()
        await model.healthTask?.value
        XCTAssertEqual(model.screen, .settings, "the form is left alone while it is open")

        model.closeSettings()

        XCTAssertEqual(
            model.screen, .setup,
            "waiting for another health refresh would leave the blocker unshown"
        )
    }

    func testClosingSettingsLandsOnTheDashboardWhenNothingBlocks() async {
        let (model, _) = await model(health: report(allGreen()))
        model.openSettings()
        model.closeSettings()
        XCTAssertEqual(model.screen, .dashboard)
    }

    // MARK: Every prerequisite gets a row

    func testAPrerequisiteMissingFromTheReportStillGetsARow() async {
        // `blocking` treats an unreported check as a blocker, so dropping it
        // from the rows puts the panel on setup with nothing naming the reason.
        let partial = Array(allGreen().dropFirst())
        let (model, _) = await model(health: report(partial))

        XCTAssertEqual(model.screen, .setup)
        XCTAssertEqual(
            model.setupSteps.map(\.id), SetupPrerequisites.ordered,
            "one row per prerequisite, reported or not"
        )
        XCTAssertEqual(model.setupSteps.first, .notReported(id: "calendar-access"))
        XCTAssertFalse(model.setupSteps.first?.isMet ?? true)
    }

    func testAReportedPrerequisiteCarriesItsFinding() async {
        let (model, _) = await model(health: report(accessDenied()))
        guard case let .checked(finding) = model.setupSteps.first else {
            return XCTFail("the reported check has to carry its finding, for its remediation")
        }
        XCTAssertEqual(finding.id, "calendar-access")
        XCTAssertNotNil(finding.remediation)
    }

    // MARK: The screen

    func testThePanelOpensOnSetupWhileAPrerequisiteIsUnmet() async {
        let (model, _) = await model(health: report(accessDenied()))

        XCTAssertEqual(model.screen, .setup)
        XCTAssertEqual(model.setupBlocker?.id, "calendar-access")
    }

    func testTheSetupScreenGivesWayToTheDashboardOnceEverythingIsMet() async {
        let (model, recorder) = await model(health: report(accessDenied()))
        XCTAssertEqual(model.screen, .setup)

        recorder.health = report(allGreen())
        model.refreshHealth()
        await model.healthTask?.value

        XCTAssertEqual(model.screen, .dashboard)
        XCTAssertNil(model.setupBlocker)
    }

    /// Settings is somewhere the user asked to be. A health refresh arriving
    /// while they are editing must not throw the form away.
    func testAHealthRefreshDoesNotYankTheUserOutOfSettings() async {
        let (model, recorder) = await model(health: report(allGreen()))
        model.openSettings()
        XCTAssertEqual(model.screen, .settings)

        recorder.health = report(accessDenied())
        model.refreshHealth()
        await model.healthTask?.value

        XCTAssertEqual(
            model.screen, .settings,
            "the setup screen can wait until they leave the form they opened"
        )
    }
}
