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
        defer {
            if let output {
                try? lines.joined(separator: "\n").appending("\n")
                    .write(toFile: output, atomically: true, encoding: .utf8)
            }
        }

        let store = EventKitStore()
        do {
            try store.requestAccess()
        } catch {
            emit("error: \(error.localizedDescription)")
            Foundation.exit(ExitCode.permissionError)
        }

        let calendars: [CalendarRef]
        do {
            calendars = try store.calendars()
        } catch {
            emit("error: \(error.localizedDescription)")
            throw ArgumentParser.ExitCode(ExitCode.partialFailure)
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
    }
}
