import XCTest
@testable import WorkSyncCore

/// The source-name field. It was the one per-source control still reading and
/// writing the model's draft directly, so a setter retained while one source was
/// selected could put its text into the next source's field — and committing
/// then renamed the wrong source.
final class SourceNameDraftTests: XCTestCase {
    private var handles = SourceHandles()
    private lazy var personal = handles.mint("personal")
    private lazy var travel = handles.mint("travel")

    func testTheFieldShowsItsOwnersText() {
        var field = SourceNameDraft()
        field.seed(personal, id: "personal")
        field.setText("home", of: personal)
        XCTAssertEqual(field.text(of: personal, fallback: "personal"), "home")
    }

    /// A card for a source that does not own the field shows that source's own
    /// id, never someone else's half-typed name.
    func testAnotherSourcesCardShowsItsOwnID() {
        var field = SourceNameDraft()
        field.seed(personal, id: "personal")
        field.setText("home", of: personal)
        XCTAssertEqual(field.text(of: travel, fallback: "travel"), "travel")
    }

    /// The defect, in the order the reviewer reproduced it: retain A's setter,
    /// select B, deliver A's setter, commit.
    func testALateSetterFromAnotherSourceCannotWriteTheField() {
        var field = SourceNameDraft()
        field.seed(personal, id: "personal")

        // The user moves to travel; the field is re-seeded for it.
        field.seed(travel, id: "travel")
        // personal's retained setter delivers late.
        field.setText("late-personal-name", of: personal)

        XCTAssertEqual(field.text(of: travel, fallback: "travel"), "travel", "travel must not be renamed")
        XCTAssertEqual(field.pending?.handle, travel, "and the field still belongs to travel")
        XCTAssertFalse(field.isDirty, "nothing was typed into travel, so there is nothing to commit")
    }

    /// The commit half: a submit from a source that does not own the field is
    /// ignored, so it cannot stage that source's rename warning either.
    func testOnlyTheOwnerCanCommitTheField() {
        var field = SourceNameDraft()
        field.seed(travel, id: "travel")
        field.setText("wanderlust", of: travel)

        XCTAssertNil(field.draft(of: personal), "personal's submit has nothing to commit")
        XCTAssertEqual(field.draft(of: travel)?.text, "wanderlust")
    }

    func testSeedingForANewSourceDiscardsTheOldText() {
        var field = SourceNameDraft()
        field.seed(personal, id: "personal")
        field.setText("half-typed", of: personal)

        field.seed(travel, id: "travel")
        XCTAssertEqual(field.text(of: travel, fallback: "travel"), "travel")
        XCTAssertEqual(field.text(of: personal, fallback: "personal"), "personal", "and it is gone, not hidden")
    }

    func testDirtyTracksTheOwnersTypingOnly() {
        var field = SourceNameDraft()
        field.seed(personal, id: "personal")
        XCTAssertFalse(field.isDirty)

        field.setText("home", of: travel)
        XCTAssertFalse(field.isDirty, "a non-owner's text is not typing")

        field.setText("home", of: personal)
        XCTAssertTrue(field.isDirty)
    }

    func testRevertingPutsTheOwnersIDBack() {
        var field = SourceNameDraft()
        field.seed(personal, id: "personal")
        field.setText("home", of: personal)

        field.revert()
        XCTAssertEqual(field.text(of: personal, fallback: "personal"), "personal")
        XCTAssertFalse(field.isDirty)
    }

    func testMarkingCommittedSettlesTheField() {
        var field = SourceNameDraft()
        field.seed(personal, id: "personal")
        field.setText("home", of: personal)

        field.markCommitted("home")
        XCTAssertFalse(field.isDirty, "a second commit must not raise the same rename again")
        XCTAssertEqual(field.text(of: personal, fallback: "home"), "home")
    }

    // MARK: What a commit reports

    /// The outcomes a caller has to stop for. `renameError` could not say this:
    /// a caller that does not read it carries on regardless.
    func testARefusalAndAnOpenConfirmationBlockTheAction() {
        XCTAssertTrue(SourceNameCommit.rejected(reason: "…").blocksAction)
        XCTAssertTrue(SourceNameCommit.awaitingConfirmation.blocksAction)
    }

    func testSettledAndRenamedDoNotBlockTheAction() {
        XCTAssertFalse(SourceNameCommit.settled.blocksAction)
        XCTAssertFalse(SourceNameCommit.renamed("home").blocksAction)
    }

    func testRemoveAllEmptiesTheField() {
        var field = SourceNameDraft()
        field.seed(personal, id: "personal")
        field.removeAll()
        XCTAssertNil(field.pending)
        XCTAssertEqual(field.text(of: personal, fallback: "personal"), "personal")
    }
}
