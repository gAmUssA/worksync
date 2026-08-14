import ArgumentParser
import Foundation
import WorkSyncCore
import WorkSyncKit

struct Calendars: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List accounts and calendars with identifiers."
    )

    @Option(name: .long, help: "Also write the listing to this file (open(1) swallows stdout)")
    var output: String?

    func run() throws {
        var lines: [String] = []
        func emit(_ line: String) {
            print(line)
            lines.append(line)
        }
        /// Flushed explicitly, never from a `defer`: Foundation.exit() does not
        /// run defer blocks, and --output exists precisely for GUI launches where
        /// stdout is discarded — a failure would otherwise leave no trace at all.
        func flush() {
            guard let output else { return }
            try? lines.joined(separator: "\n").appending("\n")
                .write(toFile: output, atomically: true, encoding: .utf8)
        }
        func die(_ error: Error) -> Never {
            lines.append("error: \(error.localizedDescription)") // stderr copy comes from fail()
            flush()
            fail(error)
        }

        let store = EventKitStore()
        do {
            try store.requestAccess()
        } catch {
            die(error)
        }

        let calendars: [CalendarRef]
        do {
            calendars = try store.calendars()
        } catch {
            die(error)
        }

        let byAccount = Dictionary(grouping: calendars, by: \.accountTitle)
        for account in byAccount.keys.sorted() {
            emit("Account: \(account)")
            for cal in byAccount[account]!.sorted(by: { $0.title < $1.title }) {
                let access = cal.allowsModifications ? "read-write" : "read-only"
                emit("  \(cal.title)  [\(access)]  id=\(cal.id)")
            }
        }
        if byAccount.isEmpty {
            emit("No calendar accounts found. Add accounts in System Settings > Internet Accounts.")
        }
        flush()
    }
}
