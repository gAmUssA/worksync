import XCTest
@testable import WorkSyncCore

final class SettingsMessagePolicyTests: XCTestCase {
    /// The case that sent a user in circles: a write failed, then they cleared
    /// a row to fix something else. Save is disabled because of the empty row,
    /// but the footer was still explaining the old write error.
    func testALiveValidationProblemWinsOverAStaleWriteError() {
        XCTAssertEqual(
            SettingsMessagePolicy.footerMessage(
                validationProblem: "Only-mirror list for “personal”: An entry cannot be blank.",
                saveError: "Could not write config: permission denied"
            ),
            "Only-mirror list for “personal”: An entry cannot be blank."
        )
    }

    func testTheWriteErrorShowsWhenTheFormIsValid() {
        XCTAssertEqual(
            SettingsMessagePolicy.footerMessage(
                validationProblem: nil,
                saveError: "Could not write config: permission denied"
            ),
            "Could not write config: permission denied"
        )
    }

    func testNothingToSay() {
        XCTAssertNil(SettingsMessagePolicy.footerMessage(validationProblem: nil, saveError: nil))
    }

    func testAValidationProblemAloneIsShown() {
        XCTAssertEqual(
            SettingsMessagePolicy.footerMessage(validationProblem: "blank row", saveError: nil),
            "blank row"
        )
    }
}
