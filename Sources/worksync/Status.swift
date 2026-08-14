import ArgumentParser
import Foundation
import WorkSyncCore
import WorkSyncKit

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Managed-event counts per source, and last-run info."
    )

    @OptionGroup var configOption: ConfigOption

    func run() throws {
        let config = loadConfigOrExit(path: configOption.config)

        // Last run first: when something is wrong, "nothing has run in three
        // days" is the answer far more often than any count below (SPEC §11.2).
        if let lastRun = LastRunStore.load() {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            let stale = lastRun.isStale(intervalMinutes: config.general.intervalMinutes)
            let staleNote = stale ? "  (STALE — expected every \(config.general.intervalMinutes)m)" : ""
            if lastRun.succeeded {
                print("Last sync: \(formatter.string(from: lastRun.finishedAt)) — \(lastRun.summary)\(staleNote)")
            } else {
                print("Last sync: \(formatter.string(from: lastRun.finishedAt)) — FAILED\(staleNote)")
                if let message = lastRun.errorMessage {
                    print("  \(message)")
                }
            }
        } else {
            print("Last sync: never (no run has completed on this machine)")
        }

        let store = EventKitStore()
        requestAccessOrExit(store)

        // Reuse the purge sweep: it already finds every managed event across
        // every calendar, including any stranded by a since-changed config.
        let scan = PurgeEngine.scan(store: store, now: Date(), sourceFilter: nil)
        for failure in scan.scanFailures {
            FileHandle.standardError.write(Data("warning: could not scan \(failure)\n".utf8))
        }

        let counts = scan.countsBySource
        let configured = Set(config.sources.map(\.id))

        print("")
        if counts.isEmpty {
            print("No managed events found.")
        } else {
            for sourceID in counts.keys.sorted() {
                // An id present on the calendars but absent from config means
                // orphaned events — the id was renamed or the source removed,
                // and only `purge --source` can reach them (SPEC §4.1).
                let orphaned = configured.contains(sourceID)
                    ? ""
                    : "  (ORPHANED — not in config; recover with `worksync purge --source \(sourceID)`)"
                print("\(sourceID): \(counts[sourceID]!) event(s)\(orphaned)")
            }
        }
        for sourceID in configured.sorted() where counts[sourceID] == nil {
            print("\(sourceID): 0 event(s)")
        }

        if !scan.isComplete {
            fail(
                "\(scan.scanFailures.count) calendar(s) could not be scanned; counts are a lower bound.",
                ExitCodes.partialFailure
            )
        }
    }
}
