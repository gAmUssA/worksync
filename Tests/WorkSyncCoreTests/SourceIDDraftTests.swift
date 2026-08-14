import XCTest
@testable import WorkSyncCore

/// The regression these exist for: the settings field used to send every
/// keystroke at the rename policy, so typing into a saved source's id opened
/// the orphan-warning alert on the first character and could commit a partial
/// id. Every test below is a step of the editing sequence that used to break.
final class SourceIDDraftTests: XCTestCase {
    private let saved: Set<String> = ["personal"]

    private func commit(
        _ draft: SourceIDDraft,
        others: [String] = []
    ) -> SourceIDDraft.Commit {
        draft.commit(savedSourceIDs: saved, otherSourceIDs: others)
    }

    // MARK: Typing

    func testTypingDoesNotCommitAnything() {
        var draft = SourceIDDraft(id: "personal")
        // The exact sequence that used to alert on the first keystroke: delete
        // back to "p", then type "home". Nothing may happen until commit.
        for text in ["persona", "person", "pers", "per", "pe", "p", "ph", "pho", "hom", "home"] {
            draft.text = text
            XCTAssertTrue(draft.isDirty, "\"\(text)\" differs from the committed id")
        }
        XCTAssertEqual(draft.committedID, "personal", "typing must not touch the working config")
    }

    func testAnIntermediateKeystrokeIsNeverWhatGetsConfirmed() {
        var draft = SourceIDDraft(id: "personal")
        draft.text = "p" // one keystroke in
        draft.text = "home" // finished typing
        XCTAssertEqual(commit(draft), .confirm(from: "personal", to: "home"))
    }

    // MARK: Commit outcomes

    func testCommittingTheSameIDIsANoOp() {
        let draft = SourceIDDraft(id: "personal")
        XCTAssertEqual(commit(draft), .unchanged)
    }

    func testWhitespaceOnlyEditsAreNotRenames() {
        var draft = SourceIDDraft(id: "personal")
        draft.text = "  personal  "
        XCTAssertEqual(commit(draft), .unchanged, "trimming happens before comparing")
        XCTAssertFalse(draft.isDirty)
    }

    func testRenamingASavedSourceAsksFirst() {
        var draft = SourceIDDraft(id: "personal")
        draft.text = "home"
        XCTAssertEqual(commit(draft), .confirm(from: "personal", to: "home"))
    }

    func testRenamingAnUnsavedSourceAppliesWithoutAsking() {
        var draft = SourceIDDraft(id: "source-2") // never written to disk
        draft.text = "family"
        XCTAssertEqual(commit(draft), .apply("family"), "nothing can be orphaned under an id that was never saved")
    }

    func testTheCommittedValueIsTheTrimmedOne() {
        var draft = SourceIDDraft(id: "source-2")
        draft.text = "  family  "
        XCTAssertEqual(
            commit(draft), .apply("family"),
            "an id with surrounding whitespace fails validate() at save time"
        )
    }

    // MARK: Rejection

    func testAnEmptyIDIsRejected() {
        var draft = SourceIDDraft(id: "source-2")
        draft.text = "   "
        guard case .rejected = commit(draft) else {
            return XCTFail("an empty id would produce marker worksync://v1//<key>")
        }
    }

    func testASlashIsRejectedInTheFieldRatherThanAtSaveTime() {
        var draft = SourceIDDraft(id: "source-2")
        draft.text = "work/home"
        guard case let .rejected(reason) = commit(draft) else {
            return XCTFail("\"/\" separates marker fields and corrupts every marker written under the id")
        }
        XCTAssertTrue(reason.contains("/"), "the message must name the offending character: \(reason)")
    }

    func testCollidingWithAnotherSourceIsRejected() {
        var draft = SourceIDDraft(id: "source-2")
        draft.text = "personal"
        guard case .rejected = commit(draft, others: ["personal"]) else {
            return XCTFail("two sources with one id make firstIndex(where:) resolve to the wrong one")
        }
    }

    func testCollisionIsCaseInsensitive() {
        var draft = SourceIDDraft(id: "source-2")
        draft.text = "PERSONAL"
        guard case .rejected = commit(draft, others: ["personal"]) else {
            return XCTFail("ConfigLoader.validate compares lowercased, so this would fail on save")
        }
    }

    func testASourceMayKeepItsOwnIDWithoutCollidingWithItself() {
        let draft = SourceIDDraft(id: "personal")
        XCTAssertEqual(commit(draft, others: ["work"]), .unchanged)
    }

    // MARK: Lifecycle

    func testCancellingRestoresTheOldID() {
        var draft = SourceIDDraft(id: "personal")
        draft.text = "home"
        draft.revert()
        XCTAssertEqual(draft.text, "personal", "the field must not keep showing a name the config does not have")
        XCTAssertFalse(draft.isDirty)
    }

    func testConfirmingMakesTheNewIDTheBaseline() {
        var draft = SourceIDDraft(id: "personal")
        draft.text = "home"
        draft.markCommitted("home")
        XCTAssertEqual(
            commit(draft), .unchanged,
            "a second commit must not re-ask about a rename that already happened"
        )
    }

    func testTheOldIDIsStillWarnedAboutWhenRenamingBack() {
        var draft = SourceIDDraft(id: "personal")
        draft.text = "home"
        draft.markCommitted("home")
        draft.text = "personal"
        XCTAssertEqual(
            commit(draft), .apply("personal"),
            "\"home\" was never saved, so renaming away from it orphans nothing"
        )
    }

    // MARK: Recovery message

    func testTheWarningNamesTheOriginalIDInTheRecoveryCommand() {
        // Recovery is by the id the events actually carry, which is the old one.
        XCTAssertEqual(
            SourceRenamePolicy.recoveryCommand(forOrphansOf: "personal"),
            "worksync purge --source personal"
        )
    }
}
