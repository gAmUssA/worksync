import XCTest
@testable import WorkSyncCore

/// An example config that drifts from the code is worse than none: it teaches
/// options that do not exist and hides ones that do. These tests are the reason
/// it can be trusted.
final class ExampleConfigTests: XCTestCase {
    /// Repo root, derived from this file's own path so the test works from any
    /// working directory.
    private static var repoRoot: String {
        // .../Tests/WorkSyncCoreTests/ExampleConfigTests.swift -> repo root
        var path = #filePath as NSString
        for _ in 0 ..< 3 {
            path = path.deletingLastPathComponent as NSString
        }
        return path as String
    }

    private static var examplePath: String {
        (repoRoot as NSString).appendingPathComponent("config.example.toml")
    }

    func testEmbeddedCopyMatchesTheFile() throws {
        // The embedded string is generated from the file; if someone edits the
        // example and forgets scripts/generate-example-config.sh, `worksync
        // init` would silently write the old one.
        let onDisk = try String(contentsOfFile: Self.examplePath, encoding: .utf8)
        XCTAssertEqual(
            ExampleConfig.contents, onDisk,
            "config.example.toml changed — run scripts/generate-example-config.sh"
        )
    }

    func testExampleParsesAndValidates() throws {
        // Shipping an example that does not load would be the worst possible
        // first-run experience.
        let config = try ConfigLoader.parse(ExampleConfig.contents)
        XCTAssertEqual(config.sources.count, 2)
        XCTAssertEqual(config.sources[0].id, "personal")
        XCTAssertEqual(config.sources[1].id, "travel")
    }

    func testExampleDocumentsEveryConfigKey() {
        // Adding a config key without documenting it fails here. The list is
        // the checklist: it is meant to be edited alongside the parser.
        let keys = [
            // [general]
            "window_days", "interval_minutes", "timezone", "log_level",
            "notify", "change_driven", "change_debounce_seconds",
            // [target] and per-source
            "account", "calendar",
            "id", "title_template", "target_calendar",
            "coalesce", "coalesce_gap_minutes",
            "min_duration_minutes", "max_duration_minutes",
            "padding_before_minutes", "padding_after_minutes",
            "skip_weekdays", "include_all_day", "skip_if_work_busy", "availability",
        ]
        for key in keys {
            XCTAssertTrue(
                ExampleConfig.contents.contains("\(key) ="),
                "config.example.toml does not document \(key)"
            )
        }
    }

    func testEveryOptionCarriesAnExplanation() {
        // The point of the example is the comments. A key with no comment
        // anywhere above it is an option the reader has to guess at.
        let lines = ExampleConfig.contents.split(separator: "\n", omittingEmptySubsequences: false)
        var sawCommentSinceBlankLine = false
        var undocumented: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                sawCommentSinceBlankLine = false
                continue
            }
            if trimmed.hasPrefix("#") {
                sawCommentSinceBlankLine = true
                continue
            }
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                continue
            }
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            // The second source is a worked example, so its keys repeat ones
            // already explained above; only require a first explanation.
            if !sawCommentSinceBlankLine, !undocumented.contains(key) {
                undocumented.append(key)
            }
        }

        // The travel source deliberately repeats keys under their own short
        // comments; anything genuinely bare shows up here.
        XCTAssertTrue(
            undocumented.isEmpty,
            "these options appear with no comment explaining them: \(undocumented.joined(separator: ", "))"
        )
    }

    func testDefaultsInTheExampleMatchTheCodeDefaults() throws {
        // A comment claiming a default the code does not use is a documentation
        // bug that only shows up as confusion months later.
        let config = try ConfigLoader.parse(ExampleConfig.contents)
        let defaults = GeneralConfig()

        XCTAssertEqual(config.general.timezone, defaults.timezone)
        XCTAssertEqual(config.general.logLevel, defaults.logLevel)
        XCTAssertEqual(config.general.notify, defaults.notify)
        XCTAssertEqual(config.general.changeDriven, defaults.changeDriven)
        XCTAssertEqual(config.general.changeDebounceSeconds, defaults.changeDebounceSeconds)
        XCTAssertEqual(config.general.windowDays, defaults.windowDays)
        XCTAssertEqual(config.general.intervalMinutes, defaults.intervalMinutes)

        // The documented per-source defaults, on the keys where the example
        // states "0 means…" or "off by default".
        let travel = config.sources[1]
        XCTAssertEqual(travel.maxDurationMinutes, 0, "example documents 0 as the no-maximum default")
        XCTAssertTrue(travel.skipWeekdays.isEmpty, "example documents an empty skip list as the default")
    }
}
