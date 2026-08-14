import ArgumentParser
import Foundation
import WorkSyncCore

// Explicit entry point (no @main): the menubar mode owns an NSApplication
// lifecycle and must instantiate its delegate itself (SPEC §3.1 rule 3).

/// Launched by LaunchServices — the login item, Finder, or `open` — rather than
/// from a terminal: no arguments and no controlling terminal. The intent there
/// is the menu bar app, not a usage message printed where nobody will see it.
/// Running the binary from a shell keeps its CLI behavior, and `worksync
/// menubar` works explicitly in both cases.
let launchedAsApp = CommandLine.arguments.count == 1
    && isatty(STDOUT_FILENO) == 0
    && isatty(STDIN_FILENO) == 0

if launchedAsApp {
    MainActor.assumeIsolated {
        MenubarApp.run(configPath: ConfigLoader.defaultPath)
    }
} else {
    WorkSync.main()
}
