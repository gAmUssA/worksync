import ArgumentParser
import Foundation

// Explicit entry point (no @main): the menubar subcommand owns an NSApplication
// lifecycle and must instantiate its delegate itself (SPEC §3.1 rule 3).
WorkSync.main()
