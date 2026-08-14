import XCTest
@testable import WorkSyncCore

final class SourceRenamePolicyTests: XCTestCase {
    private let saved: Set<String> = ["personal", "travel"]

    func testRenamingASavedSourceWarns() {
        // Its events carry the old id and become unreachable by normal syncs.
        XCTAssertTrue(SourceRenamePolicy.needsWarning(renaming: "personal", to: "home", savedSourceIDs: saved))
    }

    func testRenamingABrandNewSourceDoesNotWarn() {
        // Never saved, so no event can carry its id yet — warning here would
        // train the user to dismiss the dialog that matters.
        XCTAssertFalse(SourceRenamePolicy.needsWarning(renaming: "source-2", to: "study", savedSourceIDs: saved))
    }

    func testNoChangeDoesNotWarn() {
        XCTAssertFalse(SourceRenamePolicy.needsWarning(renaming: "personal", to: "personal", savedSourceIDs: saved))
    }

    func testTypingOneCharacterAtATimeStillOnlyWarnsForSavedIDs() {
        // A text field fires per keystroke; each intermediate value is a rename
        // away from a saved id, and each genuinely would orphan.
        for intermediate in ["persona", "person", "perso"] {
            XCTAssertTrue(
                SourceRenamePolicy.needsWarning(renaming: "personal", to: intermediate, savedSourceIDs: saved)
            )
        }
    }

    func testRecoveryCommandNamesTheOldID() {
        XCTAssertEqual(
            SourceRenamePolicy.recoveryCommand(forOrphansOf: "personal"),
            "worksync purge --source personal"
        )
    }
}
