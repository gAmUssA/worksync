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

    // MARK: Source ID string forms

    private func assertSourceIDPreserved(_ rawID: String, expectedID: String) throws {
        let fixture = """
        [target]
        account = "Work"
        calendar = "Calendar"

        [[source]]
        # This block is carefully documented.
        id = \(rawID)  # stable source identity
        account = "iCloud"
        calendar = "Personal"

        # Colleagues see only this placeholder.
        title_template = "Busy"
        """
        let (text, outcome, expected) = try saveFixture(fixture) {
            $0.sources[0].titleTemplate = "Unavailable"
        }
        XCTAssertEqual(outcome, .preserved)
        XCTAssertEqual(expected.sources[0].id, expectedID)
        XCTAssertEqual(try ConfigLoader.parse(text), expected)
        XCTAssertEqual(text, fixture.replacingOccurrences(
            of: "title_template = \"Busy\"", with: "title_template = \"Unavailable\""
        ), "only the edited field should change; ID spelling, comments and layout must survive")
    }

    func testLiteralSourceIDPreservesBlockWhenAnotherFieldChanges() throws {
        try assertSourceIDPreserved("'personal'", expectedID: "personal")
    }

    func testBasicSourceIDPreservesBlockWhenAnotherFieldChanges() throws {
        try assertSourceIDPreserved(#""personal""#, expectedID: "personal")
    }

    func testLiteralSourceIDPreservesBackslashesQuotesAndHash() throws {
        try assertSourceIDPreserved(##"'a\nb\\c\"#team'"##, expectedID: ##"a\nb\\c\"#team"##)
    }

    func testBasicSourceIDDecodesUnicodeEscapeForBlockMatching() throws {
        try assertSourceIDPreserved(#""\u0070ersonal""#, expectedID: "personal")
    }

    // MARK: Hand-wrapped arrays

    /// A user who lists more than two or three entries wraps the array, and
    /// `title_matches` / `title_excludes` are exactly the kind of list that
    /// grows. Rewriting only the key's own line used to orphan the remaining
    /// lines, and the unparseable result cost the user every comment in the
    /// file when the writer fell back to a full rewrite.
    private static let wrappedArrayFixture = """
    # Hand-formatted, and it is going to stay that way.
    [general]
    window_days = 21

    [target]
    account = "Work"
    calendar = "Calendar"

    [[source]]
    id = "personal"
    account = "iCloud"
    calendar = "Personal"
    # Weekends are already mine.
    skip_weekdays = [           # trimmed by hand
      # Saturday is non-negotiable.
      "sat",
      "sun",                    # and Sunday, mostly
    ]                           # the working week is what colleagues care about
    # Only the meetings that really block time.
    title_matches = [
      "1:1",
      "interview",
    ]
    title_excludes = [
      "tentative",
    ]  # nothing tentative is real yet
    title_template = "Busy"
    """

    /// Saves through the real on-disk path, because `outcome` is the only place
    /// a silent fall back to full serialization shows up.
    private func saveFixture(
        _ fixture: String,
        mutate: (inout Config) -> Void
    ) throws -> (text: String, outcome: ConfigWriteOutcome, config: Config) {
        let directory = NSTemporaryDirectory() + "worksync-writer-\(UUID().uuidString)"
        let path = directory + "/config.toml"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try fixture.write(toFile: path, atomically: true, encoding: .utf8)

        var updated = try ConfigLoader.parse(fixture)
        mutate(&updated)
        let outcome = try ConfigWriter.save(updated, to: path)
        return try (String(contentsOfFile: path, encoding: .utf8), outcome, updated)
    }

    /// Every comment in the file, standalone or trailing, in the order written.
    /// Trailing ones count: dropping the `# why` after a closing bracket is
    /// exactly the loss these assertions exist to catch, and a filter that only
    /// looked at whole comment lines would call that file unchanged.
    private func comments(in text: String) -> [String] {
        var found: [String] = []
        for line in text.components(separatedBy: "\n") {
            var quote: Character?
            var escaped = false
            for (offset, character) in line.enumerated() {
                if let open = quote {
                    if escaped {
                        escaped = false
                    } else if open == "\"", character == "\\" {
                        escaped = true
                    } else if character == open {
                        quote = nil
                    }
                    continue
                }
                if character == "\"" || character == "'" {
                    quote = character
                    continue
                }
                if character == "#" {
                    let start = line.index(line.startIndex, offsetBy: offset)
                    found.append(String(line[start...]).trimmingCharacters(in: .whitespaces))
                    break
                }
            }
        }
        return found
    }

    func testEditingAWrappedSkipWeekdaysKeepsTheFileIntact() throws {
        let fixture = Self.wrappedArrayFixture
        let (text, outcome, expected) = try saveFixture(fixture) { $0.sources[0].skipWeekdays = [1] }

        XCTAssertEqual(outcome, .preserved, "the line edit must hold: \n\(text)")
        XCTAssertEqual(comments(in: text), comments(in: fixture), "every comment must survive")
        XCTAssertEqual(try ConfigLoader.parse(text), expected)
        XCTAssertTrue(text.contains("""
        skip_weekdays = [           # trimmed by hand
          # Saturday is non-negotiable.
          # and Sunday, mostly
          "sun",
        ]                           # the working week is what colleagues care about
        """), "the array must stay wrapped so its comments have somewhere to live: \n\(text)")
        XCTAssertFalse(text.contains("\"sat\""), "the old elements must be gone, not orphaned: \n\(text)")
    }

    func testEditingAWrappedTitleMatchesKeepsTheFileIntact() throws {
        let fixture = Self.wrappedArrayFixture
        let (text, outcome, expected) = try saveFixture(fixture) {
            $0.sources[0].titleMatches = ["standup"]
        }

        XCTAssertEqual(outcome, .preserved, "the line edit must hold: \n\(text)")
        XCTAssertEqual(comments(in: text), comments(in: fixture), "every comment must survive")
        XCTAssertEqual(try ConfigLoader.parse(text), expected)
        XCTAssertTrue(text.contains("title_matches = [\"standup\"]"), text)
        XCTAssertFalse(text.contains("\"interview\""), "the old elements must be gone: \n\(text)")
    }

    func testEditingAWrappedTitleExcludesKeepsTheFileIntact() throws {
        let fixture = Self.wrappedArrayFixture
        let (text, outcome, expected) = try saveFixture(fixture) {
            $0.sources[0].titleExcludes = ["hold", "optional"]
        }

        XCTAssertEqual(outcome, .preserved, "the line edit must hold: \n\(text)")
        XCTAssertEqual(comments(in: text), comments(in: fixture), "every comment must survive")
        XCTAssertEqual(try ConfigLoader.parse(text), expected)
        XCTAssertTrue(text.contains("title_excludes = [\"hold\", \"optional\"]"), text)
    }

    func testAWrappedArrayCanBeEmptied() throws {
        let fixture = Self.wrappedArrayFixture
        let (text, outcome, expected) = try saveFixture(fixture) { $0.sources[0].titleMatches = [] }

        XCTAssertEqual(outcome, .preserved, "the line edit must hold: \n\(text)")
        XCTAssertEqual(comments(in: text), comments(in: fixture), "every comment must survive")
        XCTAssertEqual(try ConfigLoader.parse(text), expected)
        XCTAssertTrue(text.contains("title_matches = []"), text)
    }

    /// A wrapped array whose only comment sits after the closing bracket has
    /// nothing to keep inside it, so it collapses — and the comment rides along
    /// to the line the key ends up on.
    func testTheCommentAfterAWrappedArraysClosingBracketSurvives() throws {
        let fixture = Self.wrappedArrayFixture
        let (text, _, _) = try saveFixture(fixture) { $0.sources[0].titleExcludes = ["hold"] }

        let line = try XCTUnwrap(text.components(separatedBy: "\n").first { $0.contains("title_excludes =") })
        XCTAssertTrue(line.contains("title_excludes = [\"hold\"]"), line)
        XCTAssertTrue(
            line.contains("# nothing tentative is real yet"),
            "the explanation after the closing bracket must travel with the key: \(line)"
        )
    }

    /// SPEC §4.3 calls losing a user's comments unacceptable data loss, and a
    /// span rewrite that still parses would report `.preserved` while doing it —
    /// no warning, no fallback, nothing for the user to notice.
    func testEveryCommentInsideAWrappedArraySurvives() throws {
        let fixture = Self.wrappedArrayFixture
        let (text, outcome, _) = try saveFixture(fixture) { $0.sources[0].skipWeekdays = [1] }

        XCTAssertEqual(outcome, .preserved, "no warning is issued on this path, so nothing may be lost")
        for comment in [
            "# trimmed by hand", // on the opening line
            "# Saturday is non-negotiable.", // standalone, between elements
            "# and Sunday, mostly", // trailing an element
            "# the working week is what colleagues care about", // after the bracket
        ] {
            XCTAssertTrue(text.contains(comment), "lost a comment from inside the array: \(comment)\n\(text)")
        }
    }

    func testEditingOneWrappedArrayLeavesTheOthersByteIdentical() throws {
        let fixture = Self.wrappedArrayFixture
        let (text, _, _) = try saveFixture(fixture) { $0.sources[0].skipWeekdays = [1] }

        for block in [
            "title_matches = [\n  \"1:1\",\n  \"interview\",\n]",
            "title_excludes = [\n  \"tentative\",\n]  # nothing tentative is real yet",
        ] {
            XCTAssertTrue(text.contains(block), "an untouched wrapped array must not be reflowed: \n\(text)")
        }
    }

    func testASingleLineArrayStillChangesOnlyItsOwnLine() throws {
        let fixture = Self.wrappedArrayFixture
            .replacingOccurrences(
                of: "title_excludes = [\n  \"tentative\",\n]  # nothing tentative is real yet",
                with: "title_excludes = [\"tentative\"]  # nothing tentative is real yet"
            )
        let (text, outcome, expected) = try saveFixture(fixture) {
            $0.sources[0].titleExcludes = ["hold"]
        }

        XCTAssertEqual(outcome, .preserved)
        XCTAssertEqual(try ConfigLoader.parse(text), expected)

        let before = fixture.components(separatedBy: "\n")
        let after = text.components(separatedBy: "\n")
        XCTAssertEqual(before.count, after.count, "a single-line array must not change the line count")
        let differing = zip(before, after).filter { $0 != $1 }
        XCTAssertEqual(differing.count, 1, "exactly one line should differ")
        XCTAssertEqual(differing.first?.1, "title_excludes = [\"hold\"]  # nothing tentative is real yet")
    }

    // MARK: Literal strings

    /// TOML has two string forms, and the writer only ever emits one of them —
    /// but the loader accepts both, so a hand-written config can contain a
    /// bracket or a `#` inside single quotes. Reading either as syntax made an
    /// edit run past its own key: the scan took the `[` in `'['` for an array
    /// opener and the `]` in the later `']'` for its close, deleting the
    /// comment and the whole `title_excludes` key in between.
    private static let literalStringFixture = """
    [general]
    window_days = 21

    [target]
    account = "Work"
    calendar = "Calendar"

    [[source]]
    id = "work-a"
    account = "iCloud"
    calendar = "Personal"
    title_matches = ['[']
    # unrelated important comment
    title_excludes = [']']
    coalesce = true
    """

    func testABracketInsideALiteralStringDoesNotSwallowLaterKeys() throws {
        let fixture = Self.literalStringFixture
        let (text, outcome, expected) = try saveFixture(fixture) {
            $0.sources[0].titleMatches = ["new"]
        }

        XCTAssertEqual(outcome, .preserved, "a single-line edit must not need the fallback: \n\(text)")
        XCTAssertEqual(comments(in: text), comments(in: fixture), "every comment must survive")
        XCTAssertEqual(try ConfigLoader.parse(text), expected)
        XCTAssertTrue(text.contains("title_excludes = [']']"), "a later key was eaten: \n\(text)")
        XCTAssertTrue(text.contains("coalesce = true"), "a later key was eaten: \n\(text)")

        let before = fixture.components(separatedBy: "\n")
        let after = text.components(separatedBy: "\n")
        XCTAssertEqual(before.count, after.count, "line count must not change")
        let differing = zip(before, after).filter { $0 != $1 }
        XCTAssertEqual(differing.count, 1, "exactly one line should differ: \n\(text)")
        XCTAssertEqual(differing.first?.1, "title_matches = [\"new\"]")
    }

    func testAHashInsideALiteralStringIsNotMistakenForAComment() throws {
        let fixture = Self.literalStringFixture
            .replacingOccurrences(of: "coalesce = true", with: "title_template = 'Busy #1'")
        let (text, outcome, expected) = try saveFixture(fixture) {
            $0.sources[0].titleTemplate = "Unavailable"
        }

        XCTAssertEqual(outcome, .preserved, "a single-line edit must not need the fallback: \n\(text)")
        XCTAssertEqual(comments(in: text), comments(in: fixture), "every comment must survive")
        XCTAssertEqual(try ConfigLoader.parse(text), expected)
        XCTAssertTrue(text.contains("title_template = \"Unavailable\""), text)
        XCTAssertFalse(text.contains("#1"), "the rest of the literal must not be left behind: \n\(text)")
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

    // MARK: Reporting what survived

    func testANormalSaveReportsThatCommentsSurvived() throws {
        let directory = NSTemporaryDirectory() + "worksync-writer-\(UUID().uuidString)"
        let path = directory + "/config.toml"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try original.write(toFile: path, atomically: true, encoding: .utf8)

        var config = try loaded()
        config.general.windowDays = 45

        XCTAssertEqual(try ConfigWriter.save(config, to: path), .preserved)
        XCTAssertNil(ConfigWriteOutcome.preserved.warning, "nothing to warn about on the normal path")
    }

    func testWritingANewFileIsNotReportedAsCommentLoss() throws {
        // There were no comments to lose, so warning here would train the user
        // to ignore the warning that matters.
        let directory = NSTemporaryDirectory() + "worksync-writer-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        XCTAssertEqual(try ConfigWriter.save(loaded(), to: directory + "/config.toml"), .preserved)
    }

    func testFallingBackToAFullRewriteIsReportedRatherThanSilent() {
        // The user's comments and layout are gone at this point. A save that
        // reports plain success here is the one case where the UI would be
        // actively lying about what it did to the file.
        XCTAssertNotNil(
            ConfigWriteOutcome.reserialized.warning,
            "comment loss must be surfaced, not inferred from a diff later"
        )
        XCTAssertTrue(
            ConfigWriteOutcome.reserialized.warning?.contains(".bak") == true,
            "the warning has to say where the original went"
        )
    }

    func testAnInvalidConfigFailsWithItsOwnReasonNotARoundTripComplaint() throws {
        // Validating only via the reload check produced "neither the line edit
        // nor a full rewrite reloaded correctly", which names no field and
        // reads like a writer bug rather than a typo in the id.
        let directory = NSTemporaryDirectory() + "worksync-writer-\(UUID().uuidString)"
        let path = directory + "/config.toml"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try original.write(toFile: path, atomically: true, encoding: .utf8)

        var broken = try loaded()
        broken.sources[0].id = "team/personal"

        XCTAssertThrowsError(try ConfigWriter.save(broken, to: path)) { error in
            guard case .invalidSourceID = error as? ConfigError else {
                return XCTFail("expected ConfigError.invalidSourceID, got \(error)")
            }
        }
    }

    func testAnEmptyIDIsRefusedBeforeAnythingIsWritten() throws {
        let directory = NSTemporaryDirectory() + "worksync-writer-\(UUID().uuidString)"
        let path = directory + "/config.toml"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try original.write(toFile: path, atomically: true, encoding: .utf8)

        var broken = try loaded()
        broken.sources[0].id = ""

        XCTAssertThrowsError(try ConfigWriter.save(broken, to: path))
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), original)
    }
}
