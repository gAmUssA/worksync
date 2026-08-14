import ArgumentParser
import Foundation
import WorkSyncCore
import WorkSyncKit

struct Purge: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Delete ALL worksync-managed events (or one source's).",
        discussion: """
        Scans every calendar on every account within ±365 days — not just the \
        currently configured targets — so it also collects events stranded by a \
        since-changed config, such as a renamed source id.

        Exit codes: 0 when the sweep was complete and everything asked for was \
        done; 3 when a calendar could not be scanned, a deletion failed, or \
        another worksync process held the run lock. A non-zero exit always means \
        "the calendar may still contain managed events" — safe to re-run.
        """
    )

    @Option(name: .long, help: "Only purge events created under this source id")
    var source: String?

    @Flag(name: .long, help: "Actually delete. Without it, only the count is printed.")
    var yes = false

    func run() throws {
        let store = EventKitStore()
        requestAccessOrExit(store)

        // Take the lock BEFORE scanning when we intend to delete, so the sweep
        // cannot observe a calendar that a sync pass is midway through writing.
        // A count-only run needs no lock: it mutates nothing.
        var lock: RunLock?
        if yes {
            do {
                guard let acquired = try RunLock.acquire() else {
                    // Unlike a sync, purge exiting 0 here would be a lie: the
                    // process holding the lock is running a sync, not a purge,
                    // so nobody is doing this work. Automation must be able to
                    // tell "cleaned up" from "did nothing".
                    fail("another worksync process is running; nothing was deleted", ExitCodes.partialFailure)
                }
                lock = acquired
            } catch {
                fail(error)
            }
        }
        defer { lock?.unlock() }

        let scan = PurgeEngine.scan(store: store, now: Date(), sourceFilter: source)

        for failure in scan.scanFailures {
            FileHandle.standardError.write(Data("warning: could not scan \(failure)\n".utf8))
        }

        let counts = scan.countsBySource
        for sourceID in counts.keys.sorted() {
            print("\(sourceID): \(counts[sourceID]!) event(s)")
        }

        if scan.found.isEmpty {
            print(source.map { "No managed events found for source \"\($0)\"." }
                ?? "No managed events found.")
            // "Found nothing" after an incomplete sweep proves nothing.
            if !scan.isComplete {
                fail(
                    "\(scan.scanFailures.count) calendar(s) could not be scanned; "
                        + "managed events may remain. Safe to re-run.",
                    ExitCodes.partialFailure
                )
            }
            return
        }

        guard yes else {
            print("\(scan.found.count) event(s) would be deleted. Re-run with --yes to delete them.")
            if !scan.isComplete {
                fail(
                    "\(scan.scanFailures.count) calendar(s) could not be scanned; the count above is a lower bound.",
                    ExitCodes.partialFailure
                )
            }
            return
        }

        let result = PurgeEngine.delete(scan.found, store: store)
        print("deleted=\(result.deleted)")

        for failure in result.failures {
            FileHandle.standardError.write(Data("error: \(failure)\n".utf8))
        }

        if !result.failures.isEmpty || !scan.isComplete {
            var reasons: [String] = []
            if !result.failures.isEmpty {
                reasons.append("\(result.failures.count) deletion(s) failed")
            }
            if !scan.isComplete {
                reasons.append("\(scan.scanFailures.count) calendar(s) could not be scanned")
            }
            fail(reasons.joined(separator: "; ") + "; safe to re-run", ExitCodes.partialFailure)
        }
    }
}
