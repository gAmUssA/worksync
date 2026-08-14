import XCTest
@testable import WorkSyncCore

/// The fixture is the real shipped example (SPEC §13 asks for a comment-dense
/// one, and nothing is denser or more representative than the file users
/// actually get).
final class ConfigWriterTests: XCTestCase {
    private var original: String {
        ExampleConfig.contents
    }

    private func loaded() throws -> Config {
        try ConfigLoader.parse(original)
    }

    private func rewrite(_ mutate: (inout Config) -> Void) throws -> (text: String, config: Config) {
        let previous = try loaded()
        var updated = previous
        mutate(&updated)
        let text = ConfigWriter.apply(updated, previous: previous, to: original)
        return (text, updated)
    }

    /// Every comment line in the original, so a test can assert none vanished.
    private var originalComments: [String] {
        original.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("#") }
    }

    // MARK: The headline guarantee

    func testNoOpEditIsByteIdentical() throws {
        let previous = try loaded()
        let text = ConfigWriter.apply(previous, previous: previous, to: original)
        XCTAssertEqual(text, original, "a save with no changes must not touch the file")
    }

    func testSingleFieldEditPreservesEveryComment() throws {
        let (text, _) = try rewrite { $0.general.windowDays = 45 }

        let survivors = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("#") }
        XCTAssertEqual(survivors, originalComments, "every comment must survive a scalar edit")
    }

    func testSingleFieldEditChangesOnlyThatLine() throws {
        let (text, _) = try rewrite { $0.general.windowDays = 45 }

        let before = original.components(separatedBy: "\n")
        let after = text.components(separatedBy: "\n")
        XCTAssertEqual(before.count, after.count, "line count must not change")

        let differing = zip(before, after).enumerated().filter { $0.element.0 != $0.element.1 }
        XCTAssertEqual(differing.count, 1, "exactly one line should differ")
        XCTAssertTrue(differing.first?.element.1.contains("window_days = 45") == true)
    }

    func testEditedFileReloadsToTheNewValue() throws {
        let (text, expected) = try rewrite { $0.general.windowDays = 45 }
        XCTAssertEqual(try ConfigLoader.parse(text), expected)
    }

    /// The shipped example puts its explanations in comment blocks ABOVE each
    /// key, so it cannot exercise same-line comments. Hand-written configs
    /// routinely use them, and losing one is exactly the silent damage this
    /// writer exists to prevent — so it gets its own fixture.
    private static let trailingCommentFixture = """
    [general]
    window_days = 21            # rolling sync horizon from "now"
    interval_minutes = 10       # how often the menu bar app runs

    [target]
    account = "Work"            # EKSource title
    calendar = "Calendar"

    [[source]]
    id = "personal"
    account = "iCloud"
    calendar = "Personal"
    title_template = "Busy"     # what colleagues see
    """

    func testTrailingCommentOnTheEditedLineSurvives() throws {
        let fixture = Self.trailingCommentFixture
        let previous = try ConfigLoader.parse(fixture)
        var updated = previous
        updated.general.windowDays = 45

        let text = ConfigWriter.apply(updated, previous: previous, to: fixture)
        let line = try XCTUnwrap(
            text.components(separatedBy: "\n").first { $0.contains("window_days =") }
        )
        XCTAssertTrue(line.contains("45"), line)
        XCTAssertTrue(
            line.contains("# rolling sync horizon from \"now\""),
            "the explanation on that line must survive the edit: \(line)"
        )
        XCTAssertEqual(try ConfigLoader.parse(text), updated)
    }

    func testUneditedTrailingCommentsAreUntouched() throws {
        let fixture = Self.trailingCommentFixture
        let previous = try ConfigLoader.parse(fixture)
        var updated = previous
        updated.general.windowDays = 45

        let text = ConfigWriter.apply(updated, previous: previous, to: fixture)
        XCTAssertTrue(text.contains("interval_minutes = 10       # how often the menu bar app runs"))
        XCTAssertTrue(text.contains("account = \"Work\"            # EKSource title"))
        XCTAssertTrue(text.contains("title_template = \"Busy\"     # what colleagues see"))
    }

    func testEditingAValueThatHasATrailingCommentInASource() throws {
        let fixture = Self.trailingCommentFixture
        let previous = try ConfigLoader.parse(fixture)
        var updated = previous
        updated.sources[0].titleTemplate = "Unavailable"

        let text = ConfigWriter.apply(updated, previous: previous, to: fixture)
        let line = try XCTUnwrap(
            text.components(separatedBy: "\n").first { $0.contains("title_template =") }
        )
        XCTAssertTrue(line.contains("\"Unavailable\""), line)
        XCTAssertTrue(line.contains("# what colleagues see"), line)
        XCTAssertEqual(try ConfigLoader.parse(text), updated)
    }

    // MARK: Sources

    func testEditingOneSourceLeavesTheOtherUntouched() throws {
        let (text, _) = try rewrite { $0.sources[0].minDurationMinutes = 30 }

        // The travel block's distinctive lines must be byte-identical.
        for marker in ["title_template = \"✈️ Flight\"", "padding_before_minutes = 120", "include_all_day = true"] {
            XCTAssertTrue(text.contains(marker), "travel source lost: \(marker)")
        }
        let survivors = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("#") }
        XCTAssertEqual(survivors, originalComments)
    }

    func testAddingASource() throws {
        let (text, expected) = try rewrite { config in
            var added = SourceConfig(id: "study", account: "iCloud", calendar: "Study")
            added.titleTemplate = "Focus"
            added.coalesce = true
            config.sources.append(added)
        }

        let reloaded = try ConfigLoader.parse(text)
        XCTAssertEqual(reloaded, expected)
        XCTAssertEqual(reloaded.sources.map(\.id), ["personal", "travel", "study"])
        XCTAssertEqual(reloaded.sources[2].titleTemplate, "Focus")
        XCTAssertTrue(reloaded.sources[2].coalesce)
    }

    func testRemovingASource() throws {
        let (text, expected) = try rewrite { $0.sources.removeFirst() }

        let reloaded = try ConfigLoader.parse(text)
        XCTAssertEqual(reloaded, expected)
        XCTAssertEqual(reloaded.sources.map(\.id), ["travel"])
        XCTAssertFalse(text.contains("id = \"personal\""), "the removed block must be gone, not just ignored")
    }

    func testReorderingSourcesSurvivesARoundTrip() throws {
        // Order decides who wins cross-source dedup (SPEC §4.1), so this is a
        // behavior change disguised as a cosmetic one.
        let (text, expected) = try rewrite { $0.sources.reverse() }

        let reloaded = try ConfigLoader.parse(text)
        XCTAssertEqual(reloaded, expected)
        XCTAssertEqual(reloaded.sources.map(\.id), ["travel", "personal"])

        // And the blocks genuinely moved, rather than ids being swapped in place.
        let travelIndex = try XCTUnwrap(text.range(of: "id = \"travel\""))
        let personalIndex = try XCTUnwrap(text.range(of: "id = \"personal\""))
        XCTAssertLessThan(travelIndex.lowerBound, personalIndex.lowerBound)
    }

    func testRenamingASourceIDRewritesItsBlock() throws {
        let (text, expected) = try rewrite { $0.sources[0].id = "home" }
        let reloaded = try ConfigLoader.parse(text)
        XCTAssertEqual(reloaded, expected)
        XCTAssertEqual(reloaded.sources.map(\.id), ["home", "travel"])
    }

    // MARK: Value formatting

    func testWeekdaysAreWrittenInWeekOrder() throws {
        let (text, expected) = try rewrite { $0.sources[0].skipWeekdays = [7, 1] } // Sat, Sun
        XCTAssertTrue(
            text.contains("skip_weekdays = [\"sat\", \"sun\"]"),
            "week order reads better than component order"
        )
        XCTAssertEqual(try ConfigLoader.parse(text), expected)
    }

    func testQuotesInsideAValueAreEscaped() throws {
        let (text, expected) = try rewrite { $0.sources[0].titleTemplate = "Busy \"private\"" }
        XCTAssertEqual(try ConfigLoader.parse(text), expected)
    }

    func testAHashInsideAStringIsNotMistakenForAComment() throws {
        // "Busy #1" must round-trip intact, not get truncated at the #.
        let (text, expected) = try rewrite { $0.sources[0].titleTemplate = "Busy #1" }
        let reloaded = try ConfigLoader.parse(text)
        XCTAssertEqual(reloaded, expected)
        XCTAssertEqual(reloaded.sources[0].titleTemplate, "Busy #1")
    }

    // MARK: Fallback serialization

    func testSerializationRoundTrips() throws {
        let config = try loaded()
        XCTAssertEqual(try ConfigLoader.parse(ConfigWriter.serialize(config)), config)
    }

    func testSerializedOutputCoversEveryFieldSoNothingIsSilentlyLost() throws {
        var config = try loaded()
        config.sources[0].maxDurationMinutes = 240
        config.sources[0].skipWeekdays = [7, 1]
        config.general.changeDriven = true
        XCTAssertEqual(try ConfigLoader.parse(ConfigWriter.serialize(config)), config)
    }

    // MARK: On disk

    func testSaveWritesABackupAndReloads() throws {
        let directory = NSTemporaryDirectory() + "worksync-writer-\(UUID().uuidString)"
        let path = directory + "/config.toml"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try original.write(toFile: path, atomically: true, encoding: .utf8)

        var config = try loaded()
        config.general.windowDays = 45
        try ConfigWriter.save(config, to: path)

        XCTAssertEqual(try ConfigLoader.load(path: path), config)
        let backup = try String(contentsOfFile: path + ".bak", encoding: .utf8)
        XCTAssertEqual(backup, original, "the backup must be the file as it was before the write")
    }

    func testSaveToANewPathSerializes() throws {
        let directory = NSTemporaryDirectory() + "worksync-writer-\(UUID().uuidString)"
        let path = directory + "/config.toml"
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let config = try loaded()
        try ConfigWriter.save(config, to: path)
        XCTAssertEqual(try ConfigLoader.load(path: path), config)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: path + ".bak"),
            "nothing to back up when the file did not exist"
        )
    }

    func testSaveRefusesToWriteAConfigThatWouldNotLoad() throws {
        // An id containing "/" is rejected by validation, so no output can be
        // correct — the file must be left alone rather than half-written.
        let directory = NSTemporaryDirectory() + "worksync-writer-\(UUID().uuidString)"
        let path = directory + "/config.toml"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try original.write(toFile: path, atomically: true, encoding: .utf8)

        var broken = try loaded()
        broken.sources[0].id = "team/personal"

        XCTAssertThrowsError(try ConfigWriter.save(broken, to: path))
        XCTAssertEqual(
            try String(contentsOfFile: path, encoding: .utf8), original,
            "the existing config must survive a refused write untouched"
        )
    }
}
