import XCTest
@testable import WorkSyncCore

/// Both rules here fail invisibly. Too eager and every write triggers a
/// permanent extra no-op pass; too lazy and the fast path silently never
/// fires. Neither shows up as an error anywhere.
final class ChangeTriggerPolicyTests: XCTestCase {
    private let policy = ChangeTriggerPolicy(debounceSeconds: 20)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: Debounce

    func testAChangeArmsTheTimerForTheConfiguredDebounce() {
        XCTAssertEqual(policy.action(now: now, lastWriteAt: nil), .armTimer(20))
    }

    func testTheDebounceComesFromConfig() {
        var config = Config(
            general: GeneralConfig(),
            target: TargetConfig(account: "Work", calendar: "Calendar"),
            sources: []
        )
        config.general.changeDebounceSeconds = 45
        XCTAssertEqual(ChangeTriggerPolicy(config: config).action(now: now, lastWriteAt: nil), .armTimer(45))
    }

    func testABurstAlwaysReArmsRatherThanQueueing() {
        // Calendar.app posts several notifications for what the user
        // experienced as one edit. Each must re-arm the SAME timer — the
        // caller relies on this action being identical every time, so that
        // invalidating and rescheduling collapses the burst into one pass
        // instead of scheduling one pass per notification.
        for offset in [0.0, 0.2, 0.5, 1.0, 3.0] {
            XCTAssertEqual(
                policy.action(now: now.addingTimeInterval(offset), lastWriteAt: nil),
                .armTimer(20),
                "every notification in a burst must produce the same re-arm"
            )
        }
    }

    func testAZeroDebounceIsStillValidAndStillGoesThroughTheTimer() {
        // Deliberately not "fire inline": the notification arrives on an
        // arbitrary queue while the database is still settling.
        let eager = ChangeTriggerPolicy(debounceSeconds: 0)
        XCTAssertTrue(eager.isValid)
        XCTAssertEqual(eager.action(now: now, lastWriteAt: nil), .armTimer(0))
    }

    // MARK: Own-write echo

    func testOurOwnWriteIsIgnored() {
        // Without this, every writing pass schedules exactly one no-op pass
        // behind it — forever, on every machine.
        XCTAssertEqual(
            policy.action(now: now.addingTimeInterval(1), lastWriteAt: now),
            .ignoreEcho
        )
    }

    func testTheEchoWindowIsFiveSeconds() {
        XCTAssertEqual(policy.action(now: now.addingTimeInterval(4.9), lastWriteAt: now), .ignoreEcho)
        XCTAssertEqual(
            policy.action(now: now.addingTimeInterval(5.1), lastWriteAt: now), .armTimer(20),
            "past the window, a change is the user's own and must be honoured"
        )
    }

    func testAChangeWithNoPriorWriteIsNeverAnEcho() {
        XCTAssertEqual(policy.action(now: now, lastWriteAt: nil), .armTimer(20))
    }

    func testAnOldWriteDoesNotSuppressALaterUserEdit() {
        // The window is short on purpose: suppressing for longer would drop
        // real edits made right after a sync.
        XCTAssertEqual(
            policy.action(now: now.addingTimeInterval(3600), lastWriteAt: now),
            .armTimer(20)
        )
    }
}

/// The lifecycle the observer goes through while the app is running.
///
/// `change_driven` and `change_debounce_seconds` are both editable in the
/// settings screen, so "start it once after the first pass" is not enough:
/// without reconciliation, turning the feature off leaves it running for the
/// rest of the process lifetime.
final class ChangeObservationPlanTests: XCTestCase {
    private func config(driven: Bool, debounce: Int = 20) -> Config {
        var general = GeneralConfig()
        general.changeDriven = driven
        general.changeDebounceSeconds = debounce
        return Config(
            general: general,
            target: TargetConfig(account: "Work", calendar: "Calendar"),
            sources: [SourceConfig(id: "personal", account: "iCloud", calendar: "Personal")]
        )
    }

    private func reconcile(
        driven: Bool,
        debounce: Int = 20,
        observing: Bool,
        currentPolicy: ChangeTriggerPolicy? = nil,
        hasCompletedAPass: Bool = true
    ) -> ChangeObservationPlan {
        ChangeObservationPlan.reconcile(
            config: config(driven: driven, debounce: debounce),
            observing: observing,
            currentPolicy: currentPolicy,
            hasCompletedAPass: hasCompletedAPass
        )
    }

    // MARK: Starting

    func testStartsWhenEnabledAfterASuccessfulPass() {
        XCTAssertEqual(reconcile(driven: true, observing: false), .start(ChangeTriggerPolicy(debounceSeconds: 20)))
    }

    func testDoesNotStartBeforeAnyPassHasSucceeded() {
        // A successful pass is the proof that access is granted. Observing
        // earlier registers something that can never fire while reporting
        // itself as working.
        XCTAssertEqual(reconcile(driven: true, observing: false, hasCompletedAPass: false), .doNothing)
    }

    func testDoesNotStartWhenDisabled() {
        XCTAssertEqual(reconcile(driven: false, observing: false), .doNothing)
    }

    func testDoesNotRestartAnObserverThatIsAlreadyRunning() {
        XCTAssertEqual(
            reconcile(driven: true, observing: true, currentPolicy: ChangeTriggerPolicy(debounceSeconds: 20)),
            .doNothing
        )
    }

    // MARK: Stopping — the regression this exists for

    func testTurningTheSettingOffStopsAnObserverAlreadyRunning() {
        // The bug: the observer was started once and never revisited, so
        // switching "React to calendar changes" off did nothing until the app
        // was restarted, and passes kept firing.
        XCTAssertEqual(
            reconcile(driven: false, observing: true, currentPolicy: ChangeTriggerPolicy(debounceSeconds: 20)),
            .stop
        )
    }

    func testStoppingIsNotGatedOnAPassHavingSucceeded() {
        // Starting is gated; stopping never is. A user turning the feature off
        // must be obeyed regardless of what else is true.
        XCTAssertEqual(
            reconcile(driven: false, observing: true, hasCompletedAPass: false),
            .stop
        )
    }

    // MARK: Reconfiguring

    func testChangingTheDebounceUpdatesThePolicyWithoutRestarting() {
        // The notification carries no payload, so a debounce change needs no
        // re-registration — and re-registering would open a window in which
        // changes go unseen for no reason.
        XCTAssertEqual(
            reconcile(
                driven: true, debounce: 45, observing: true,
                currentPolicy: ChangeTriggerPolicy(debounceSeconds: 20)
            ),
            .updatePolicy(ChangeTriggerPolicy(debounceSeconds: 45))
        )
    }

    func testAnUnchangedDebounceIsNotChurned() {
        XCTAssertEqual(
            reconcile(
                driven: true, debounce: 20, observing: true,
                currentPolicy: ChangeTriggerPolicy(debounceSeconds: 20)
            ),
            .doNothing
        )
    }

    // MARK: Sequences

    func testAFullOnOffOnCycleSettles() {
        // Walks the states the settings screen can actually produce.
        var observing = false
        var policy: ChangeTriggerPolicy?

        func apply(_ plan: ChangeObservationPlan) {
            switch plan {
            case let .start(p): observing = true; policy = p
            case let .updatePolicy(p): policy = p
            case .stop: observing = false; policy = nil
            case .doNothing: break
            }
        }

        apply(reconcile(driven: true, observing: observing, currentPolicy: policy))
        XCTAssertTrue(observing)

        apply(reconcile(driven: false, observing: observing, currentPolicy: policy))
        XCTAssertFalse(observing, "off must actually stop it")
        XCTAssertNil(policy, "a stopped observer must not keep a stale policy")

        apply(reconcile(driven: true, debounce: 30, observing: observing, currentPolicy: policy))
        XCTAssertTrue(observing, "and it must come back on")
        XCTAssertEqual(policy?.debounceSeconds, 30, "with the debounce as configured now")

        // Settled: reconciling again changes nothing.
        XCTAssertEqual(reconcile(driven: true, debounce: 30, observing: observing, currentPolicy: policy), .doNothing)
    }
}

/// Echo suppression keys off this, so what counts as "wrote" is load-bearing.
final class ApplyResultWroteAnythingTests: XCTestCase {
    func testCreatesUpdatesAndDeletesAllCount() {
        for mutate in [
            { (r: inout ApplyResult) in r.created = 1 },
            { (r: inout ApplyResult) in r.updated = 1 },
            { (r: inout ApplyResult) in r.deleted = 1 },
        ] {
            var result = ApplyResult()
            mutate(&result)
            XCTAssertTrue(result.wroteAnything)
        }
    }

    func testAConvergedPassDidNotWrite() {
        // The steady state: nothing changed, so nothing was written, so there
        // is no echo to suppress. Counting this as a write would blind the
        // fast path to the user's own edits for the whole window after every
        // single pass — which is most passes.
        var result = ApplyResult()
        result.unchanged = 12
        XCTAssertFalse(result.wroteAnything)
    }

    func testSkippedIsNotAWrite() {
        var result = ApplyResult()
        result.skipped = 3
        XCTAssertFalse(result.wroteAnything)
    }

    func testAnEmptyResultDidNotWrite() {
        XCTAssertFalse(ApplyResult().wroteAnything)
    }
}
