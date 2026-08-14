import ArgumentParser
import Foundation
import WorkSyncCore

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Write a fully commented example config to get started.",
        discussion: """
        Creates ~/.config/worksync/config.toml from the bundled example, which \
        documents every option and its default inline. Refuses to overwrite an \
        existing config — use --print to send it to stdout instead.
        """
    )

    @OptionGroup var configOption: ConfigOption

    @Flag(name: .customLong("print"), help: "Print the example to stdout instead of writing a file")
    var printOnly = false

    func run() throws {
        guard let example = Self.exampleContents() else {
            fail("the bundled example config is missing from this build", ExitCodes.partialFailure)
        }

        if printOnly {
            Swift.print(example, terminator: "")
            return
        }

        let path = configOption.config
        guard !FileManager.default.fileExists(atPath: path) else {
            // Never clobber a real config: it is hand-edited by definition, and
            // the comments in it may be the user's own.
            fail(
                "\(path) already exists. Edit it directly, or run `worksync init --print` to see the example.",
                ExitCodes.configError
            )
        }

        do {
            try FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try example.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            fail("could not write \(path): \(error.localizedDescription)", ExitCodes.partialFailure)
        }

        Swift.print("Wrote \(path)")
        Swift.print("Next: run `worksync calendars` to find your account and calendar names,")
        Swift.print("edit the file, then `worksync sync --dry-run` to preview.")
    }

    /// The example ships inside the binary rather than as a resource file, so
    /// `worksync init` works from a bare binary on PATH as well as from the
    /// app bundle.
    static func exampleContents() -> String? {
        ExampleConfig.contents
    }
}
