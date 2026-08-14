import Foundation

/// Everything a pass learned on the way to its plan, so the CLI (and later the
/// menu bar) can report it without re-deriving anything.
///
/// These counts exist because each represents work that silently did NOT
/// happen: events with no usable identity, events an earlier source already
/// claimed, blocks the work calendar already covers. A user looking at
/// "created=3" when they expected 12 needs these numbers to find out why.
public struct PassDiagnostics: Equatable, Sendable {
    public var fetchedBySource: [String: Int] = [:]
    public var targetBySource: [String: String] = [:]
    public var unidentifiableBySource: [String: Int] = [:]
    public var duplicatesDroppedBySource: [String: Int] = [:]
    public var conflictSkippedBySource: [String: Int] = [:]
}

public struct PlannedPass: Sendable {
    public let plan: SyncPlan
    public let diagnostics: PassDiagnostics
}

/// The read-and-plan half of a pass (SPEC §5 steps 1–8), in the core so the
/// whole pipeline — including the ordering the milestones depend on — is
/// testable against the in-memory store rather than only through the CLI.
public enum SyncPipeline {
    public static func plan(
        config: Config,
        store: CalendarStore,
        now: Date,
        calendar: Calendar = .current
    ) throws -> PlannedPass {
        let calendars = try store.calendars()
        let resolved = try Resolver.resolve(config: config, calendars: calendars)
        let window = SyncPlanner.window(now: now, windowDays: config.general.windowDays)

        var diagnostics = PassDiagnostics()

        // Steps 2–3: fetch per source, in config order — the order decides who
        // wins cross-source dedup below.
        var inputs: [SourcePlanInput] = []
        for source in config.sources {
            guard let sourceCal = resolved.sourceCalendars[source.id],
                  let targetCal = resolved.targetCalendars[source.id] else { continue }
            let events = try store.events(in: sourceCal, from: window.start, to: window.end)
            diagnostics.fetchedBySource[source.id] = events.count
            diagnostics.targetBySource[source.id] = targetCal.title

            let unidentifiable = SyncPlanner.unidentifiable(events).count
            if unidentifiable > 0 {
                diagnostics.unidentifiableBySource[source.id] = unidentifiable
            }
            inputs.append(SourcePlanInput(source: source, targetCalendar: targetCal, events: events))
        }

        // Steps 4–5: dedup across sources, then transform.
        let multi = SyncPlanner.desiredAcrossSources(inputs, window: window, calendar: calendar)
        diagnostics.duplicatesDroppedBySource = multi.duplicatesDropped

        // Step 6: one fetch of the target calendars, reused by both the
        // conflict check and reconciliation.
        var existing: [StoredEvent] = []
        for target in resolved.allTargets {
            existing += try store.events(in: target, from: window.start, to: window.end)
        }

        // Step 7: drop blocks the work calendar already covers.
        let conflict = SyncPlanner.applyConflictSkips(
            to: multi.blocks, existingOnTargets: existing, sources: config.sources
        )
        diagnostics.conflictSkippedBySource = conflict.skippedBySource

        // Step 8: reconcile.
        var plan = SyncPlanner.reconcile(desired: conflict.kept, existingOnTargets: existing)
        plan.skippedCount = conflict.skipped

        return PlannedPass(plan: plan, diagnostics: diagnostics)
    }
}
