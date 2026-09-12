import XCTest
@testable import WorkSyncCore

/// The settings form's list editor is SwiftUI and this package has no UI test
/// target, so the rules it enforces live here, where they can be run.
final class TitleFilterEntryTests: XCTestCase {
    // MARK: Judging one entry

    func testAnOrdinaryEntryIsValid() {
        XCTAssertEqual(TitleFilterEntry.check("1:1", against: []), .valid("1:1"))
    }

    func testAnUntouchedFieldIsEmptyRatherThanWrong() {
        // Nothing typed yet is not an error to show the user — it is only a
        // reason the add button stays disabled.
        XCTAssertEqual(TitleFilterEntry.check("", against: []), .empty)
        XCTAssertNil(TitleFilterEntry.message(for: .empty))
    }

    func testWhitespaceOnlyIsBlankAndExplainsWhy() {
        XCTAssertEqual(TitleFilterEntry.check("   ", against: []), .blank)
        XCTAssertEqual(TitleFilterEntry.check("\t\n", against: []), .blank)
        // "" is a substring of every title, which is why the loader refuses it.
        XCTAssertEqual(
            TitleFilterEntry.message(for: .blank),
            "An entry cannot be blank — it would match every title."
        )
    }

    func testSurroundingWhitespaceIsTrimmedRatherThanStored() {
        // " lunch " as a substring filter misses "Lunch", which is a bug the
        // user cannot see in the field.
        XCTAssertEqual(TitleFilterEntry.check("  lunch  ", against: []), .valid("lunch"))
    }

    func testAnEntryAlreadyInTheListIsRefused() {
        XCTAssertEqual(TitleFilterEntry.check("lunch", against: ["lunch"]), .duplicate("lunch"))
        XCTAssertEqual(TitleFilterEntry.check(" lunch ", against: ["lunch"]), .duplicate("lunch"))
    }

    func testDuplicatesAreJudgedTheWayThePlannerMatches() {
        // The planner compares case- and diacritic-insensitively (SPEC §4.1),
        // so these are one filter written twice, not two filters.
        XCTAssertEqual(TitleFilterEntry.check("LUNCH", against: ["lunch"]), .duplicate("LUNCH"))
        XCTAssertEqual(TitleFilterEntry.check("cafe", against: ["café"]), .duplicate("cafe"))
    }

    func testARowDoesNotCollideWithItself() {
        // Editing row 0 back to what it already says is not a duplicate.
        XCTAssertEqual(
            TitleFilterEntry.check("lunch", against: ["lunch", "gym"], excluding: 0),
            .valid("lunch")
        )
        XCTAssertEqual(
            TitleFilterEntry.check("gym", against: ["lunch", "gym"], excluding: 0),
            .duplicate("gym")
        )
    }

    func testADistinctEntryJoinsAListThatAlreadyHasOne() {
        XCTAssertEqual(TitleFilterEntry.check("gym", against: ["lunch"]), .valid("gym"))
    }

    // MARK: Adding

    func testAddingAppendsTheNormalizedText() {
        XCTAssertEqual(TitleFilterEntry.adding("  gym ", to: ["lunch"]), ["lunch", "gym"])
    }

    func testAddingRefusesWhatTheFormWouldRefuse() {
        // nil rather than the unchanged list, so a caller cannot report a
        // silent no-op as a successful add.
        XCTAssertNil(TitleFilterEntry.adding("   ", to: []))
        XCTAssertNil(TitleFilterEntry.adding("", to: []))
        XCTAssertNil(TitleFilterEntry.adding("lunch", to: ["Lunch"]))
    }

    // MARK: The list as a whole

    func testAGoodListHasNoProblem() {
        XCTAssertNil(TitleFilterEntry.problem(in: []))
        XCTAssertNil(TitleFilterEntry.problem(in: ["lunch", "gym"]))
    }

    func testARowEmptiedInPlaceIsAProblem() {
        // This is the one `adding` cannot catch: the entry was already there
        // and the user deleted its text.
        XCTAssertEqual(TitleFilterEntry.problem(in: ["lunch", ""]), TitleFilterEntry.message(for: .blank))
        XCTAssertEqual(TitleFilterEntry.problem(in: ["   "]), TitleFilterEntry.message(for: .blank))
    }

    func testTwoRowsEditedToTheSameTextAreAProblem() {
        XCTAssertEqual(
            TitleFilterEntry.problem(in: ["lunch", "LUNCH"]),
            TitleFilterEntry.message(for: .duplicate("lunch"))
        )
    }

    /// Every entry the editor can produce must survive the validation the
    /// writer runs, or the form is just moving the error later.
    func testWhatTheEditorProducesPassesConfigValidation() throws {
        var config = try ConfigLoader.parse(Self.fixture)
        config.sources[0].titleMatches = try XCTUnwrap(TitleFilterEntry.adding("  1:1  ", to: []))
        config.sources[0].titleExcludes = try XCTUnwrap(
            TitleFilterEntry.adding("tentative", to: ["hold"])
        )
        XCTAssertNoThrow(try ConfigLoader.validate(config))
    }

    // MARK: Round trip through the writer

    /// The fixture is hand-wrapped on purpose: a list a user edits in the form
    /// is exactly the one they are likely to have wrapped by hand, and the save
    /// has to come back `.preserved` rather than rewriting the file.
    private static let fixture = """
    # Mirror the personal calendar, quietly.
    [general]
    window_days = 21

    [target]
    account = "Work"
    calendar = "Calendar"

    [[source]]
    id = "personal"
    account = "iCloud"
    calendar = "Personal"
    title_template = "Busy"
    # Only the commitments that really block time.
    title_matches = [
      "1:1",
    ]
    title_excludes = ["tentative"]
    """

    func testEditingBothListsRoundTripsThroughTheWriter() throws {
        let directory = NSTemporaryDirectory() + "worksync-filters-\(UUID().uuidString)"
        let path = directory + "/config.toml"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try Self.fixture.write(toFile: path, atomically: true, encoding: .utf8)

        var config = try ConfigLoader.parse(Self.fixture)
        // The three operations the form offers, in the order it offers them.
        config.sources[0].titleMatches = try XCTUnwrap(
            TitleFilterEntry.adding("interview", to: config.sources[0].titleMatches)
        )
        config.sources[0].titleExcludes.remove(at: 0)
        config.sources[0].titleExcludes = try XCTUnwrap(
            TitleFilterEntry.adding("hold", to: config.sources[0].titleExcludes)
        )

        let outcome = try ConfigWriter.save(config, to: path)
        let written = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertEqual(outcome, .preserved, "the form must not cost the user their comments: \n\(written)")
        XCTAssertTrue(written.contains("# Mirror the personal calendar, quietly."), written)
        XCTAssertTrue(written.contains("# Only the commitments that really block time."), written)

        let reloaded = try ConfigLoader.load(path: path)
        XCTAssertEqual(reloaded, config)
        XCTAssertEqual(reloaded.sources[0].titleMatches, ["1:1", "interview"])
        XCTAssertEqual(reloaded.sources[0].titleExcludes, ["hold"])
    }

    func testClearingAListWritesAnEmptyArray() throws {
        let directory = NSTemporaryDirectory() + "worksync-filters-\(UUID().uuidString)"
        let path = directory + "/config.toml"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try Self.fixture.write(toFile: path, atomically: true, encoding: .utf8)

        // Removing the last row is the normal way back to the default, so it
        // has to be as writable as any other value.
        var config = try ConfigLoader.parse(Self.fixture)
        config.sources[0].titleMatches = []
        config.sources[0].titleExcludes = []

        XCTAssertEqual(try ConfigWriter.save(config, to: path), .preserved)
        let reloaded = try ConfigLoader.load(path: path)
        XCTAssertEqual(reloaded.sources[0].titleMatches, [])
        XCTAssertEqual(reloaded.sources[0].titleExcludes, [])
    }
}
