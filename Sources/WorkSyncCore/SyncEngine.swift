import Foundation

/// What a pass actually did, as opposed to what it planned.
public struct ApplyResult: Equatable, Sendable {
    public var created = 0
    public var updated = 0
    public var deleted = 0
    public var unchanged = 0
    public var skipped = 0
    /// Human-readable description of each write that failed. A pass continues
    /// after a failure and reports exit 3 (SPEC §9) rather than aborting
    /// half-applied with no summary.
    public var failures: [String] = []

    public var hasFailures: Bool {
        !failures.isEmpty
    }

    /// Whether this pass touched the calendar database at all.
    ///
    /// Drives echo suppression on the change-driven path (SPEC §11.2): only a
    /// pass that actually wrote can provoke the notification that would
    /// otherwise trigger the next one. `unchanged` and `skipped` deliberately
    /// do not count — treating a read-only pass as a write would suppress the
    /// user's own genuine edits for the whole echo window.
    public var wroteAnything: Bool {
        created > 0 || updated > 0 || deleted > 0
    }

    public init() {}

    /// The one summary string shown in the log, the menu bar header, and
    /// notifications — one source of truth for "what happened this pass"
    /// (SPEC §11.2).
    public var summaryLine: String {
        "created=\(created) updated=\(updated) deleted=\(deleted) skipped=\(skipped) unchanged=\(unchanged)"
            + (hasFailures ? " failed=\(failures.count)" : "")
    }
}

public enum SyncEngine {
    /// Applies a plan through the store, then commits once.
    ///
    /// Individual write failures are collected rather than thrown: a calendar
    /// that rejects one event should not strand the rest of the pass, and the
    /// next run reconciles whatever did not land (the whole design is
    /// idempotent, so a partial application is safe).
    public static func apply(_ plan: SyncPlan, store: CalendarStore) -> ApplyResult {
        var result = ApplyResult()
        result.unchanged = plan.unchangedCount
        result.skipped = plan.skippedCount

        for change in plan.changes {
            do {
                switch change {
                case let .create(block):
                    try store.create(block)
                    result.created += 1
                case let .update(eventIdentifier, block):
                    try store.update(eventIdentifier: eventIdentifier, to: block)
                    result.updated += 1
                case let .delete(eventIdentifier, _, _):
                    try store.delete(eventIdentifier: eventIdentifier)
                    result.deleted += 1
                }
            } catch {
                result.failures.append(describe(change, error: error))
            }
        }

        // Commit even when some writes failed: the ones that succeeded are
        // staged and should land.
        do {
            try store.commit()
        } catch {
            result.failures.append("commit failed: \(error.localizedDescription)")
        }

        return result
    }

    private static func describe(_ change: PlannedChange, error: Error) -> String {
        switch change {
        case let .create(block):
            "create \"\(block.title)\" [\(block.sourceID)]: \(error.localizedDescription)"
        case let .update(_, block):
            "update \"\(block.title)\" [\(block.sourceID)]: \(error.localizedDescription)"
        case let .delete(_, marker, title):
            "delete \"\(title)\" [\(marker.sourceID)]: \(error.localizedDescription)"
        }
    }
}
