import ArgumentParser
import Foundation
import WorkSyncCore
import WorkSyncKit

struct Purge: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Delete ALL worksync-managed events (or one source's)."
    )

    @Option(name: .long, help: "Only purge events created under this source id")
    var source: String?

    @Flag(name: .long, help: "Actually delete. Without it, only the count is printed.")
    var yes = false

    func run() throws {
        let store = EventKitStore()
        requestAccessOrExit(store)

        // Purge is deliberately NOT bound to the rolling sync window: it scans
        // every calendar on every account so it also collects events stranded
        // by a since-changed config — a renamed source id, a retargeted
        // calendar (SPEC §8).
        let span = PurgeScan.span(around: Date())
        let calendars: [CalendarRef]
        do {
            calendars = try store.calendars()
        } catch {
            fail(error)
        }

        var managed: [(event: StoredEvent, marker: Marker, calendar: CalendarRef)] = []
        for calendar in calendars {
            let events: [StoredEvent]
            do {
                events = try store.events(in: calendar, from: span.start, to: span.end)
            } catch {
                // One unreadable calendar must not abort the sweep; report and
                // keep going, then exit 3 so the incompleteness is visible.
                FileHandle.standardError.write(Data(
                    "warning: could not scan \(calendar.accountTitle)/\(calendar.title): \(error.localizedDescription)\n"
                        .utf8
                ))
                continue
            }
            for event in events {
                guard let marker = PurgeScan.claimable(event, sourceFilter: source) else { continue }
                managed.append((event, marker, calendar))
            }
        }

        if managed.isEmpty {
            print(source.map { "No managed events found for source \"\($0)\"." }
                ?? "No managed events found.")
            return
        }

        let bySource = Dictionary(grouping: managed, by: { $0.marker.sourceID })
        for sourceID in bySource.keys.sorted() {
            print("\(sourceID): \(bySource[sourceID]!.count) event(s)")
        }

        guard yes else {
            print("\(managed.count) event(s) would be deleted. Re-run with --yes to delete them.")
            return
        }

        // Take the lock: purging while a pass is mid-write would race the
        // reconciler over the same events (SPEC §9).
        guard let lock = RunLock() else {
            print("another sync is already running; try again in a moment")
            return
        }
        defer { lock.unlock() }

        var deleted = 0
        var failures: [String] = []
        for item in managed {
            do {
                try store.delete(eventIdentifier: item.event.eventIdentifier)
                deleted += 1
            } catch {
                failures.append("\"\(item.event.title)\": \(error.localizedDescription)")
            }
        }
        do {
            try store.commit()
        } catch {
            failures.append("commit failed: \(error.localizedDescription)")
        }

        print("deleted=\(deleted)")
        if !failures.isEmpty {
            for failure in failures {
                FileHandle.standardError.write(Data("error: \(failure)\n".utf8))
            }
            fail("\(failures.count) deletion(s) failed; safe to re-run", ExitCodes.partialFailure)
        }
    }
}
