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

        let plan: SyncPlan
        do {
            plan = try Self.plan(config: config, store: store, now: Date(), verbose: verbose)
        } catch let error as ResolutionError {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            throw ArgumentParser.ExitCode(ExitCode.configError)
        }

        if dryRun {
            printPlan(plan)
            print("dry-run: \(plan.summaryLine)")
            return
        }

        // Write path lands in M2 (bean worksync-hw8o).
        FileHandle.standardError.write(Data(
            "error: applying changes is not implemented yet (milestone M2); use --dry-run to preview.\n".utf8
        ))
        throw ArgumentParser.ExitCode(ExitCode.configError)
    }

    /// The shared read-and-plan pipeline (SPEC §5 steps 1–6, 8-as-diff).
    /// Cross-source dedup (step 5) and the conflict check (step 7) land in M3.
    static func plan(config: Config, store: CalendarStore, now: Date, verbose: Bool) throws -> SyncPlan {
        let calendars = try store.calendars()
        let resolved = try Resolver.resolve(config: config, calendars: calendars)
        let window = SyncPlanner.window(now: now, windowDays: config.general.windowDays)

        var desired: [DesiredBlock] = []
        for source in config.sources {
            guard let sourceCal = resolved.sourceCalendars[source.id],
                  let targetCal = resolved.targetCalendars[source.id] else { continue }
            let events = try store.events(in: sourceCal, from: window.start, to: window.end)
            if verbose {
                print("source \(source.id): fetched \(events.count) events from \(sourceCal.title)")
            }
            desired += SyncPlanner.desiredBlocks(
                source: source, targetCalendar: targetCal, events: events, window: window
            )
        }

        var existing: [StoredEvent] = []
        for target in resolved.allTargets {
            existing += try store.events(in: target, from: window.start, to: window.end)
        }

        return SyncPlanner.reconcile(desired: desired, existingOnTargets: existing)
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
