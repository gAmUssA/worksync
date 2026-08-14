import ArgumentParser
import Foundation
import WorkSyncCore
import WorkSyncKit

struct Sync: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run one reconciliation pass."
    )

    @OptionGroup var configOption: ConfigOption

    @Flag(name: .long, help: "Print the full plan and exit without mutating anything")
    var dryRun = false

    @Flag(name: .long, help: "Verbose output")
    var verbose = false

    func run() throws {
        let config = loadConfigOrExit(path: configOption.config)
        let store = EventKitStore()
        requestAccessOrExit(store)

        // Dry-run reads only, so it never contends for the lock.
        let lock: RunLock?
        if dryRun {
            lock = nil
        } else {
            do {
                guard let acquired = try RunLock.acquire() else {
                    // Not an error: another pass is already doing this work
                    // (SPEC §9). Only genuine contention lands here — a lock
                    // file that cannot be opened throws instead, so a broken
                    // environment can never masquerade as a healthy no-op.
                    if verbose {
                        print("another sync is already running; exiting quietly")
                    }
                    return
                }
                lock = acquired
            } catch {
                fail(error)
            }
        }
        defer { lock?.unlock() }

        let plan: SyncPlan
        do {
            plan = try Self.plan(config: config, store: store, now: Date(), verbose: verbose)
        } catch {
            // Everything the pass can throw maps through the one documented
            // contract (SPEC §8): resolution problems are config errors, a grant
            // revoked mid-run is a permission error, and backend failures are
            // re-runnable partial failures. Letting an error escape to
            // ArgumentParser instead would collapse all of them onto exit 1.
            fail(error)
        }

        if dryRun {
            printPlan(plan)
            print("dry-run: \(plan.summaryLine)")
            return
        }

        let result = SyncEngine.apply(plan, store: store)
        print(result.summaryLine)

        if result.hasFailures {
            for failure in result.failures {
                FileHandle.standardError.write(Data("error: \(failure)\n".utf8))
            }
            // Partial application is safe to re-run: reconciliation is
            // idempotent, so the next pass finishes whatever did not land.
            fail("\(result.failures.count) write(s) failed; safe to re-run", ExitCodes.partialFailure)
        }
    }

    /// The shared read-and-plan pipeline (SPEC §5, steps 1–8).
    static func plan(config: Config, store: CalendarStore, now: Date, verbose: Bool) throws -> SyncPlan {
        let calendars = try store.calendars()
        let resolved = try Resolver.resolve(config: config, calendars: calendars)
        let window = SyncPlanner.window(now: now, windowDays: config.general.windowDays)

        // Steps 2–3: fetch per source, in config order — the order decides who
        // wins cross-source dedup below.
        var inputs: [SourcePlanInput] = []
        for source in config.sources {
            guard let sourceCal = resolved.sourceCalendars[source.id],
                  let targetCal = resolved.targetCalendars[source.id] else { continue }
            let events = try store.events(in: sourceCal, from: window.start, to: window.end)
            if verbose {
                print("source \(source.id): fetched \(events.count) events from \(sourceCal.title)"
                    + " -> \(targetCal.title)")
            }
            // Never drop these silently: without an identifier they cannot be
            // reconciled idempotently, so they produce no blocker at all.
            let unidentifiable = SyncPlanner.unidentifiable(events)
            if !unidentifiable.isEmpty {
                FileHandle.standardError.write(Data(
                    "warning: source \(source.id): skipped \(unidentifiable.count) event(s) with no stable identifier\n"
                        .utf8
                ))
            }
            inputs.append(SourcePlanInput(source: source, targetCalendar: targetCal, events: events))
        }

        // Steps 4–5: dedup across sources, then transform.
        let multi = SyncPlanner.desiredAcrossSources(inputs, window: window)
        if verbose {
            for sourceID in multi.duplicatesDropped.keys.sorted() {
                print("source \(sourceID): \(multi.duplicatesDropped[sourceID]!) event(s)"
                    + " already claimed by an earlier source")
            }
        }

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
        if verbose {
            for sourceID in conflict.skippedBySource.keys.sorted() {
                print("source \(sourceID): \(conflict.skippedBySource[sourceID]!) block(s)"
                    + " skipped — work calendar already busy")
            }
        }

        // Step 8: reconcile.
        var plan = SyncPlanner.reconcile(desired: conflict.kept, existingOnTargets: existing)
        plan.skippedCount = conflict.skipped
        return plan
    }

    private func printPlan(_ plan: SyncPlan) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        func fmt(_ interval: Interval) -> String {
            "\(formatter.string(from: interval.start)) → \(formatter.string(from: interval.end))"
        }
        for change in plan.changes {
            switch change {
            case let .create(block):
                print("CREATE  [\(block.sourceID)] \"\(block.title)\"  \(fmt(block.interval))")
            case let .update(_, block):
                print("UPDATE  [\(block.sourceID)] \"\(block.title)\"  \(fmt(block.interval))")
            case let .delete(_, marker, title):
                print("DELETE  [\(marker.sourceID)] \"\(title)\"")
            }
        }
        if plan.changes.isEmpty {
            print("No changes needed.")
        }
    }
}
