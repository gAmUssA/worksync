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
            let pass = try SyncPipeline.plan(config: config, store: store, now: Date())
            report(pass.diagnostics)
            plan = pass.plan
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

        let logger = Logger(level: config.general.logLevel)
        logger.info(result.summaryLine)

        // Display state only — reconciliation never reads this back (SPEC §3).
        LastRunStore.save(LastRun(
            finishedAt: Date(),
            succeeded: !result.hasFailures,
            summary: result.summaryLine,
            errorMessage: result.failures.first
        ))

        if result.hasFailures {
            for failure in result.failures {
                FileHandle.standardError.write(Data("error: \(failure)\n".utf8))
                logger.error(failure)
            }
            // Partial application is safe to re-run: reconciliation is
            // idempotent, so the next pass finishes whatever did not land.
            fail("\(result.failures.count) write(s) failed; safe to re-run", ExitCodes.partialFailure)
        }
    }

    /// Renders what the pass learned. Warnings go to stderr because they mean
    /// work silently did not happen; the per-source detail is verbose-only.
    private func report(_ diagnostics: PassDiagnostics) {
        for sourceID in diagnostics.unidentifiableBySource.keys.sorted() {
            let message = "warning: source \(sourceID): skipped"
                + " \(diagnostics.unidentifiableBySource[sourceID]!) event(s) with no stable identifier\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
        guard verbose else { return }
        for sourceID in diagnostics.fetchedBySource.keys.sorted() {
            let target = diagnostics.targetBySource[sourceID] ?? "?"
            print("source \(sourceID): fetched \(diagnostics.fetchedBySource[sourceID]!) event(s) -> \(target)")
        }
        for sourceID in diagnostics.duplicatesDroppedBySource.keys.sorted() {
            print("source \(sourceID): \(diagnostics.duplicatesDroppedBySource[sourceID]!)"
                + " event(s) already claimed by an earlier source")
        }
        for sourceID in diagnostics.conflictSkippedBySource.keys.sorted() {
            print("source \(sourceID): \(diagnostics.conflictSkippedBySource[sourceID]!)"
                + " block(s) skipped — work calendar already busy")
        }
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
