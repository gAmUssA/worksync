import XCTest
@testable import WorkSyncCore

/// The settings form's per-source add fields. These rules used to live as a
/// `titleFilterDrafts = [:]` line in one function the view called on a
/// selection change — which adding and removing a source walked straight past.
final class TitleFilterDraftsTests: XCTestCase {
    private let matches = "matches"
    private let excludes = "excludes"

    func testTextIsReadableByTheSourceItWasTypedFor() {
        var drafts = TitleFilterDrafts()
        drafts.setText("lunch", matches, of: "a")
        XCTAssertEqual(drafts.text(matches, of: "a"), "lunch")
    }

    /// The defect, stated directly: a half-typed entry must not be visible —
    /// and so must not be committable — while a different source is selected.
    func testTextIsInvisibleToADifferentSource() {
        var drafts = TitleFilterDrafts()
        drafts.setText("lunch", matches, of: "a")
        XCTAssertEqual(drafts.text(matches, of: "b"), "", "a draft typed for “a” must not appear under “b”")
        XCTAssertNil(
            TitleFilterEntry.adding(drafts.text(matches, of: "b"), to: []),
            "and an empty draft cannot be added, so it cannot land on the wrong source"
        )
    }

    func testTextIsInvisibleWhenNothingIsSelected() {
        var drafts = TitleFilterDrafts()
        drafts.setText("lunch", matches, of: "a")
        XCTAssertEqual(drafts.text(matches, of: nil), "")
    }

    func testTypingForAnotherSourceRetiresTheOldDrafts() {
        var drafts = TitleFilterDrafts()
        drafts.setText("lunch", matches, of: "a")
        drafts.setText("gym", excludes, of: "b")
        XCTAssertEqual(drafts.text(excludes, of: "b"), "gym")
        XCTAssertEqual(drafts.text(matches, of: "b"), "", "“a”'s draft must not survive into “b”'s form")
        XCTAssertEqual(drafts.text(matches, of: "a"), "", "and it is gone, not merely hidden")
    }

    func testTheTwoFieldsOfOneSourceAreIndependent() {
        var drafts = TitleFilterDrafts()
        drafts.setText("lunch", matches, of: "a")
        drafts.setText("hold", excludes, of: "a")
        XCTAssertEqual(drafts.text(matches, of: "a"), "lunch")
        XCTAssertEqual(drafts.text(excludes, of: "a"), "hold")
    }

    func testClearingOneFieldLeavesTheOther() {
        var drafts = TitleFilterDrafts()
        drafts.setText("lunch", matches, of: "a")
        drafts.setText("hold", excludes, of: "a")
        drafts.clear(matches, of: "a")
        XCTAssertEqual(drafts.text(matches, of: "a"), "")
        XCTAssertEqual(drafts.text(excludes, of: "a"), "hold")
    }

    func testClearingFromAnotherSourceDoesNothing() {
        var drafts = TitleFilterDrafts()
        drafts.setText("lunch", matches, of: "a")
        drafts.clear(matches, of: "b")
        XCTAssertEqual(drafts.text(matches, of: "a"), "lunch")
    }

    /// A rename is the same row under a new name, so the typing stays with it —
    /// the one selection change that must NOT retire the drafts.
    func testARenamedSourceKeepsWhatWasTypedForIt() {
        var drafts = TitleFilterDrafts()
        drafts.setText("lunch", matches, of: "personal")
        drafts.rename("personal", to: "home")
        XCTAssertEqual(drafts.text(matches, of: "home"), "lunch")
        XCTAssertEqual(drafts.text(matches, of: "personal"), "")
    }

    func testRenamingADifferentSourceLeavesTheDraftAlone() {
        var drafts = TitleFilterDrafts()
        drafts.setText("lunch", matches, of: "a")
        drafts.rename("b", to: "c")
        XCTAssertEqual(drafts.text(matches, of: "a"), "lunch")
        XCTAssertEqual(drafts.text(matches, of: "c"), "")
    }

    func testRemoveAllDropsEverything() {
        var drafts = TitleFilterDrafts()
        drafts.setText("lunch", matches, of: "a")
        drafts.removeAll()
        XCTAssertEqual(drafts.text(matches, of: "a"), "")
    }

    // MARK: Committing a draft to the source it belongs to

    private func sources() -> [SourceConfig] {
        var personal = SourceConfig(id: "personal", account: "iCloud", calendar: "Personal")
        personal.titleMatches = ["1:1"]
        let travel = SourceConfig(id: "travel", account: "Google", calendar: "Travel")
        return [personal, travel]
    }

    func testCommittingAddsToTheNamedSourceAndClearsThatSourcesDraft() throws {
        var drafts = TitleFilterDrafts()
        drafts.setText("interview", matches, of: "personal")

        let committed = try XCTUnwrap(TitleFilterEntry.committingDraft(
            matches, to: \.titleMatches, ofSourceWith: "personal", in: sources(), drafts: drafts
        ))
        XCTAssertEqual(committed.sources[0].titleMatches, ["1:1", "interview"])
        XCTAssertEqual(committed.sources[1].titleMatches, [], "the other source must not gain an entry")
        XCTAssertEqual(committed.drafts.text(matches, of: "personal"), "", "the draft has landed, so it clears")
    }

    /// The defect: a commit carrying source X used to read and clear the draft
    /// of whatever was selected. Text typed for one source could be appended to
    /// another and then wiped.
    func testCommittingToOneSourceLeavesAnotherSourcesDraftAlone() {
        var drafts = TitleFilterDrafts()
        drafts.setText("standup", matches, of: "travel")

        let committed = TitleFilterEntry.committingDraft(
            matches, to: \.titleMatches, ofSourceWith: "personal", in: sources(), drafts: drafts
        )
        XCTAssertNil(committed, "there is nothing typed for “personal”, so the commit does nothing")
        XCTAssertEqual(
            drafts.text(matches, of: "travel"), "standup",
            "and the text typed for “travel” is still there to be saved"
        )
    }

    func testCommittingForASourceThatIsGoneWritesNothing() {
        var drafts = TitleFilterDrafts()
        drafts.setText("standup", matches, of: "gone")

        XCTAssertNil(TitleFilterEntry.committingDraft(
            matches, to: \.titleMatches, ofSourceWith: "gone", in: sources(), drafts: drafts
        ), "a callback for a deleted source must not write to a neighbour")
    }

    func testAnUnaddableDraftKeepsItsText() {
        // Refused, so there is nothing to clear: the user still has what they
        // typed and the reason is on screen.
        var drafts = TitleFilterDrafts()
        drafts.setText("1:1", matches, of: "personal")

        XCTAssertNil(TitleFilterEntry.committingDraft(
            matches, to: \.titleMatches, ofSourceWith: "personal", in: sources(), drafts: drafts
        ))
        XCTAssertEqual(drafts.text(matches, of: "personal"), "1:1")
    }

    func testCommittingOneFieldLeavesTheOtherFieldsDraft() throws {
        var drafts = TitleFilterDrafts()
        drafts.setText("interview", matches, of: "personal")
        drafts.setText("hold", excludes, of: "personal")

        let committed = try XCTUnwrap(TitleFilterEntry.committingDraft(
            matches, to: \.titleMatches, ofSourceWith: "personal", in: sources(), drafts: drafts
        ))
        XCTAssertEqual(committed.drafts.text(excludes, of: "personal"), "hold")
    }

    /// The whole scenario, in the order the user performs it: type a filter for
    /// one source, then do something that moves the selection without going
    /// through the view's change handler (adding a source, or removing one).
    func testADraftCannotBeSavedOntoTheSourceASelectionChangeLandsOn() {
        var drafts = TitleFilterDrafts()
        drafts.setText(" standup", matches, of: "personal")

        // addSource(): selection moves to the new row.
        let selectedAfterAdd = "source-2"
        let committed = TitleFilterEntry.adding(
            drafts.text(matches, of: selectedAfterAdd), to: []
        )
        XCTAssertNil(committed, "the new source must not inherit what was typed for “personal”")

        // removeSelectedSource(): selection falls back to the first row.
        let selectedAfterRemove = "travel"
        XCTAssertNil(
            TitleFilterEntry.adding(drafts.text(matches, of: selectedAfterRemove), to: []),
            "neither must the row the selection falls back to"
        )
    }
}
