# WorkSync Code Review (Copilot)

## Findings (ordered by severity)

### 1) High: Disabling `change_driven` does not stop the existing calendar observer
**Why it matters**
The change observer is started once after a successful pass, but the integration only starts it when `changeObserver == nil` and the current config enables the feature. There is no path that stops the observer when the setting is later turned off, and no path that replaces its policy when the debounce interval changes.

**Evidence**
- The observer is retained and guarded by `changeObserver == nil`: [Sources/worksync/MenuBar/MenuBarModel.swift](Sources/worksync/MenuBar/MenuBarModel.swift#L252-L260)
- When the observer already exists, changing `change_driven` to false or changing `change_debounce_seconds` returns without reconfiguration: [Sources/worksync/MenuBar/MenuBarModel.swift](Sources/worksync/MenuBar/MenuBarModel.swift#L252-L258)
- The observer callback continues to call `calendarDidChange`, which uses the stale retained `changePolicy`: [Sources/worksync/MenuBar/MenuBarModel.swift](Sources/worksync/MenuBar/MenuBarModel.swift#L261-L288)
- Settings can edit `change_driven` and the config is applied on the next save/pass: [Sources/worksync/MenuBar/SettingsView.swift](Sources/worksync/MenuBar/SettingsView.swift#L120-L136)

**Impact**
- Turning off change-driven sync in Settings does not actually turn it off during the current menu-bar process lifetime.
- Changing the debounce value has no effect until the app is restarted.
- Users may get unexpected extra sync passes after explicitly disabling the fast path.

**Recommendation**
Make observer configuration reconcile on every successful pass: stop and clear the observer/timer when disabled; when enabled, restart or update the observer policy when the debounce setting changes. A small `reconfigureChangeObservation(config:)` method should own this lifecycle and be directly tested.

---

### 2) Medium: The first native notification can be queued before authorization completes
**Why it matters**
On the first notification, `UserNotifier.post` calls `requestAuthorizationOnce()` and immediately submits the `UNNotificationRequest`. Authorization is asynchronous, so the request may be added before the user grants permission or before the system has completed the authorization transition. The first expected banner can therefore be lost.

**Evidence**
- Authorization is requested and then the notification is added immediately: [Sources/worksync/MenuBar/UserNotifier.swift](Sources/worksync/MenuBar/UserNotifier.swift#L25-L46)
- The authorization completion only logs the result and does not retry or submit the pending notification: [Sources/worksync/MenuBar/UserNotifier.swift](Sources/worksync/MenuBar/UserNotifier.swift#L60-L75)
- Existing tests cover notification policy and AppleScript escaping, but not the native first-authorization/post ordering: [Tests/WorkSyncCoreTests/NotificationTests.swift](Tests/WorkSyncCoreTests/NotificationTests.swift)

**Impact**
- With `notify = "always"`, the first completed pass after enabling notifications may not produce the promised native banner.
- With `notify = "errors"`, the first failure notification may be silently lost, which is the most costly notification to miss.

**Recommendation**
Make authorization completion part of the delivery flow: request authorization once, then add the pending request only after authorization succeeds. If authorization is denied, log it and let doctor surface the remediation. Preserve best-effort semantics so notification failure never fails the sync pass.

---

### 3) Medium: EventKit change observer behavior is not covered by an EventKit-backed runtime test
**Why it matters**
The pure debounce and echo policy is well tested, but the actual observer registration, object filtering, callback delivery, start/stop lifecycle, and app-run-loop interaction are not exercised in CI.

**Evidence**
- The EventKit adapter registers `.EKEventStoreChanged` against a retained store: [Sources/WorkSyncKit/EventKitChangeObserver.swift](Sources/WorkSyncKit/EventKitChangeObserver.swift#L12-L43)
- Tests cover only the pure trigger policy and write classification: [Tests/WorkSyncCoreTests/ChangeTriggerTests.swift](Tests/WorkSyncCoreTests/ChangeTriggerTests.swift)
- The observer is injected into the UI model, but no test drives the model’s observer lifecycle: [Sources/worksync/MenuBar/MenuBarModel.swift](Sources/worksync/MenuBar/MenuBarModel.swift#L101-L120)

**Impact**
- A registration or run-loop regression can silently disable the fast path while all unit tests remain green.
- The fallback timer still masks the issue, making this particularly difficult to detect from normal behavior.

**Recommendation**
Add a fake-observer/menu-model integration test for enable, debounce re-arm, echo suppression, disable, and reconfiguration. Separately keep a manual bundle-launched checklist item for a real Calendar.app edit producing a change-driven pass.

## Residual Risks

### Low: Notification delivery is intentionally best effort
The notifier correctly does not turn banner failure into sync failure, and the AppleScript fallback is escaped and tested. The remaining concern is specifically the first-run authorization ordering, not the best-effort contract itself.

### Low: The observer is intentionally started only after a successful pass
This avoids pretending the fast path works before calendar access is granted, but it means a failed initial pass will not establish change-driven observation. That is reasonable because the timer remains the guarantee; it should remain documented in the user-facing troubleshooting flow.

## Snapshot (M7 Change-Driven + Notifications Delta)
- Review type: Delta review from the previous M7 doctor/health review
- Baseline commit: `e50a66afe4476e69fe1c22fc003953c6d6d238b4` (`e50a66a`)
- Current commit reviewed: `c49b9e077309bcefd7409a433acc92b29256bb4c` (`c49b9e0`)
- Main implementation commit: `c49b9e0` - change-driven sync and desktop notifications
- Related doctor correction included in the delta: `e7b5cf3`
- Working tree at review time: clean
- Review date: 2026-08-14

## Scope Reviewed
- debounce and own-write echo suppression
- EventKit change observer registration/lifecycle
- menu-bar observer integration and re-triggering
- notification policy for off/errors/always modes
- native UserNotifications authorization and AppleScript fallback
- notification/doctor documentation and test coverage

## Verification Run
- `swift test`: **187 tests, 0 failures**

## Improvements Confirmed
- Change-trigger policy is pure and tests debounce, re-arming, zero delay, and five-second echo suppression: [Sources/WorkSyncCore/ChangeTrigger.swift](Sources/WorkSyncCore/ChangeTrigger.swift), [Tests/WorkSyncCoreTests/ChangeTriggerTests.swift](Tests/WorkSyncCoreTests/ChangeTriggerTests.swift)
- `ApplyResult.wroteAnything` correctly distinguishes real writes from unchanged/skipped passes for echo suppression: [Sources/WorkSyncCore/SyncEngine.swift](Sources/WorkSyncCore/SyncEngine.swift)
- Notification policy correctly handles off/errors/always, partial writes, lock skips, and error sounds: [Sources/WorkSyncCore/Notifications.swift](Sources/WorkSyncCore/Notifications.swift), [Tests/WorkSyncCoreTests/NotificationTests.swift](Tests/WorkSyncCoreTests/NotificationTests.swift)
- AppleScript fallback escaping covers quotes, backslashes, and newlines.
- Doctor correction avoids treating uncheckable health state as healthy.

## Assessment
The M7 policy layers are strong and well-tested, but the runtime lifecycle has two important issues: change-driven configuration is not dynamically reconfigured, and first-run native notification delivery can race authorization. Fix those before treating change-driven sync and notifications as complete.
