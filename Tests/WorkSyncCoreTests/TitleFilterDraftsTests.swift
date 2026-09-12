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
