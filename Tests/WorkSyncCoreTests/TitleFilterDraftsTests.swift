import XCTest
@testable import WorkSyncCore

/// The settings form's per-source add fields. These rules used to live as a
/// `titleFilterDrafts = [:]` line in one function the view called on a
/// selection change — which adding and removing a source walked straight past.
final class TitleFilterDraftsTests: XCTestCase {
    private let matches = "matches"
    private let excludes = "excludes"
    /// Sources are addressed by the identity the editing session minted, never
    /// by their config id — the id is data the user can change.
    private var handles = SourceHandles()

    private func handle(_ id: String) -> SourceHandle {
        handles.handle(of: id) ?? handles.mint(id)
    }

    func testTextIsReadableByTheSourceItWasTypedFor() {
        var drafts = TitleFilterDrafts()
        drafts.setText("lunch", matches, of: handle("a"))
        XCTAssertEqual(drafts.text(matches, of: handle("a")), "lunch")
    }

    /// The defect, stated directly: a half-typed entry must not be visible —
    /// and so must not be committable — while a different source is selected.
    func testTextIsInvisibleToADifferentSource() {
        var drafts = TitleFilterDrafts()
        drafts.setText("lunch", matches, of: handle("a"))
        XCTAssertEqual(drafts.text(matches, of: handle("b")), "", "a draft typed for “a” must not appear under “b”")
        XCTAssertNil(
            TitleFilterEntry.adding(drafts.text(matches, of: handle("b")), to: []),
            "and an empty draft cannot be added, so it cannot land on the wrong source"
        )
    }

    func testTextIsInvisibleWhenNothingIsSelected() {
        var drafts = TitleFilterDrafts()
        drafts.setText("lunch", matches, of: handle("a"))
        XCTAssertEqual(drafts.text(matches, of: SourceHandle?.none), "")
    }

    func testTypingForAnotherSourceRetiresTheOldDrafts() {
        var drafts = TitleFilterDrafts()
        drafts.setText("lunch", matches, of: handle("a"))
        drafts.setText("gym", excludes, of: handle("b"))
        XCTAssertEqual(drafts.text(excludes, of: handle("b")), "gym")
        XCTAssertEqual(drafts.text(matches, of: handle("b")), "", "“a”'s draft must not survive into “b”'s form")
        XCTAssertEqual(drafts.text(matches, of: handle("a")), "", "and it is gone, not merely hidden")
    }

    func testTheTwoFieldsOfOneSourceAreIndependent() {
        var drafts = TitleFilterDrafts()
        drafts.setText("lunch", matches, of: handle("a"))
        drafts.setText("hold", excludes, of: handle("a"))
        XCTAssertEqual(drafts.text(matches, of: handle("a")), "lunch")
        XCTAssertEqual(drafts.text(excludes, of: handle("a")), "hold")
    }

    func testClearingOneFieldLeavesTheOther() {
        var drafts = TitleFilterDrafts()
        drafts.setText("lunch", matches, of: handle("a"))
        drafts.setText("hold", excludes, of: handle("a"))
        drafts.clear(matches, of: handle("a"))
        XCTAssertEqual(drafts.text(matches, of: handle("a")), "")
        XCTAssertEqual(drafts.text(excludes, of: handle("a")), "hold")
    }

    func testClearingFromAnotherSourceDoesNothing() {
        var drafts = TitleFilterDrafts()
        drafts.setText("lunch", matches, of: handle("a"))
        drafts.clear(matches, of: handle("b"))
        XCTAssertEqual(drafts.text(matches, of: handle("a")), "lunch")
    }

    /// A rename moves the id, not the identity, so the draft needs no carrying
    /// across: the same handle still reads it.
    func testARenamedSourceKeepsWhatWasTypedForIt() {
        var drafts = TitleFilterDrafts()
        let personal = handle("personal")
        drafts.setText("lunch", matches, of: personal)

        handles.rename(personal, to: "home")
        XCTAssertEqual(handles.id(of: personal), "home")
        XCTAssertEqual(drafts.text(matches, of: personal), "lunch")
    }

    /// The hole a config id left: a field built before the rename commits with
    /// the id it captured. Addressed by identity there is no such field — it
    /// carries the handle, which still names the renamed source — and a handle
    /// nothing answers to any more is ignored.
    func testALateCommitCannotReOwnADraftUnderARetiredIdentity() {
        var drafts = TitleFilterDrafts()
        let live = handle("personal")
        drafts.setText("lunch", matches, of: live)

        // A source that was removed while one of its fields was still alive.
        let retired = handles.mint("ghost")
        handles.remove(retired)
        drafts.setText("stale", matches, of: retired, in: handles)

        XCTAssertEqual(drafts.text(matches, of: live), "lunch", "the live source keeps its text")
        XCTAssertEqual(drafts.text(matches, of: retired), "", "and the dead one owns nothing")
    }

    func testTypingForALiveSourceStillWorksThroughTheGuardedForm() {
        var drafts = TitleFilterDrafts()
        let personal = handle("personal")
        drafts.setText("lunch", matches, of: personal, in: handles)
        XCTAssertEqual(drafts.text(matches, of: personal), "lunch")
    }

    func testRemoveAllDropsEverything() {
        var drafts = TitleFilterDrafts()
        drafts.setText("lunch", matches, of: handle("a"))
        drafts.removeAll()
        XCTAssertEqual(drafts.text(matches, of: handle("a")), "")
    }

    // MARK: Committing a draft to the source it belongs to

    private func resolved(_ id: String) -> EditedSource {
        EditedSource(handle: handle(id), id: id)
    }

    private func sources() -> [SourceConfig] {
        var personal = SourceConfig(id: "personal", account: "iCloud", calendar: "Personal")
        personal.titleMatches = ["1:1"]
        let travel = SourceConfig(id: "travel", account: "Google", calendar: "Travel")
        return [personal, travel]
    }

    func testCommittingAddsToTheNamedSourceAndClearsThatSourcesDraft() throws {
        var drafts = TitleFilterDrafts()
        drafts.setText("interview", matches, of: handle("personal"))

        let committed = try XCTUnwrap(TitleFilterEntry.committingDraft(
            matches, to: \.titleMatches, of: resolved("personal"), in: sources(), drafts: drafts
        ))
        XCTAssertEqual(committed.sources[0].titleMatches, ["1:1", "interview"])
        XCTAssertEqual(committed.sources[1].titleMatches, [], "the other source must not gain an entry")
        XCTAssertEqual(committed.drafts.text(matches, of: handle("personal")), "", "the draft has landed, so it clears")
    }

    /// The defect: a commit carrying source X used to read and clear the draft
    /// of whatever was selected. Text typed for one source could be appended to
    /// another and then wiped.
    func testCommittingToOneSourceLeavesAnotherSourcesDraftAlone() {
        var drafts = TitleFilterDrafts()
        drafts.setText("standup", matches, of: handle("travel"))

        let committed = TitleFilterEntry.committingDraft(
            matches, to: \.titleMatches, of: resolved("personal"), in: sources(), drafts: drafts
        )
        XCTAssertNil(committed, "there is nothing typed for “personal”, so the commit does nothing")
        XCTAssertEqual(
            drafts.text(matches, of: handle("travel")), "standup",
            "and the text typed for “travel” is still there to be saved"
        )
    }

    func testCommittingForASourceThatIsGoneWritesNothing() {
        var drafts = TitleFilterDrafts()
        drafts.setText("standup", matches, of: handle("gone"))

        XCTAssertNil(TitleFilterEntry.committingDraft(
            matches, to: \.titleMatches, of: resolved("gone"), in: sources(), drafts: drafts
        ), "a callback for a deleted source must not write to a neighbour")
    }

    func testAnUnaddableDraftKeepsItsText() {
        // Refused, so there is nothing to clear: the user still has what they
        // typed and the reason is on screen.
        var drafts = TitleFilterDrafts()
        drafts.setText("1:1", matches, of: handle("personal"))

        XCTAssertNil(TitleFilterEntry.committingDraft(
            matches, to: \.titleMatches, of: resolved("personal"), in: sources(), drafts: drafts
        ))
        XCTAssertEqual(drafts.text(matches, of: handle("personal")), "1:1")
    }

    func testCommittingOneFieldLeavesTheOtherFieldsDraft() throws {
        var drafts = TitleFilterDrafts()
        drafts.setText("interview", matches, of: handle("personal"))
        drafts.setText("hold", excludes, of: handle("personal"))

        let committed = try XCTUnwrap(TitleFilterEntry.committingDraft(
            matches, to: \.titleMatches, of: resolved("personal"), in: sources(), drafts: drafts
        ))
        XCTAssertEqual(committed.drafts.text(excludes, of: handle("personal")), "hold")
    }

    /// The whole scenario, in the order the user performs it: type a filter for
    /// one source, then do something that moves the selection without going
    /// through the view's change handler (adding a source, or removing one).
    func testADraftCannotBeSavedOntoTheSourceASelectionChangeLandsOn() {
        var drafts = TitleFilterDrafts()
        drafts.setText(" standup", matches, of: handle("personal"))

        // addSource(): selection moves to the new row.
        let selectedAfterAdd = handle("source-2")
        let committed = TitleFilterEntry.adding(
            drafts.text(matches, of: selectedAfterAdd), to: []
        )
        XCTAssertNil(committed, "the new source must not inherit what was typed for “personal”")

        // removeSelectedSource(): selection falls back to the first row.
        let selectedAfterRemove = handle("travel")
        XCTAssertNil(
            TitleFilterEntry.adding(drafts.text(matches, of: selectedAfterRemove), to: []),
            "neither must the row the selection falls back to"
        )
    }
}
