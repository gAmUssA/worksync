import XCTest
@testable import WorkSyncCore

/// The question under test is product judgement, not plumbing: which passes
/// are worth interrupting someone for. Getting it wrong in the loud direction
/// is worse than it sounds — a utility that banners every ten minutes gets its
/// notifications switched off wholesale, which silences the failures too.
final class NotificationPolicyTests: XCTestCase {
    private func completed(created: Int = 0, failures: [String] = []) -> PassOutcome {
        var result = ApplyResult()
        result.created = created
        result.failures = failures
        return PassOutcome(disposition: .completed, result: result, diagnostics: nil)
    }

    // MARK: off

    func testOffPostsNothingEvenForFailures() {
        for outcome in [
            completed(created: 3),
            completed(failures: ["could not write"]),
            PassOutcome(disposition: .failed("calendar access denied"), result: nil, diagnostics: nil),
        ] {
            XCTAssertNil(
                NotificationPolicy.notification(for: outcome, mode: .off),
                "off means off — including for errors"
            )
        }
    }

    // MARK: errors (the default)

    func testErrorsModeStaysSilentOnASuccessfulPass() {
        XCTAssertNil(NotificationPolicy.notification(for: completed(created: 3), mode: .errors))
    }

    func testErrorsModeNotifiesOnAFailedPass() throws {
        let outcome = PassOutcome(disposition: .failed("calendar access denied"), result: nil, diagnostics: nil)
        let note = try XCTUnwrap(NotificationPolicy.notification(for: outcome, mode: .errors))
        XCTAssertTrue(note.isError)
    }

    func testPartialWriteFailuresNotifyEvenInErrorsMode() throws {
        // The pass "completed" but did not do what it was asked. Reporting
        // this as success is the failure mode that makes a sync tool
        // untrustworthy: it says it worked and the blocker is not there.
        let note = try XCTUnwrap(
            NotificationPolicy.notification(for: completed(created: 1, failures: ["x"]), mode: .errors)
        )
        XCTAssertTrue(note.isError)
        XCTAssertTrue(note.title.lowercased().contains("error"), note.title)
    }

    // MARK: always

    func testAlwaysNotifiesOnSuccess() throws {
        let note = try XCTUnwrap(NotificationPolicy.notification(for: completed(created: 3), mode: .always))
        XCTAssertFalse(note.isError)
    }

    func testTheBodyIsTheExactPassSummary() throws {
        // One source of truth: the same string the log line and the menu bar
        // header carry, so three surfaces cannot describe one pass differently.
        let outcome = completed(created: 3)
        let note = try XCTUnwrap(NotificationPolicy.notification(for: outcome, mode: .always))
        XCTAssertEqual(note.body, outcome.summary)
        XCTAssertEqual(note.body, outcome.result?.summaryLine)
    }

    func testAFailureBodyCarriesTheUnderlyingError() throws {
        // "Sync failed" with no reason just sends the user to the log to find
        // what could have been on screen.
        let outcome = PassOutcome(
            disposition: .failed("Calendar \"Personal\" not found in account \"iCloud\""),
            result: nil, diagnostics: nil
        )
        let note = try XCTUnwrap(NotificationPolicy.notification(for: outcome, mode: .always))
        XCTAssertTrue(note.body.contains("not found"), note.body)
    }

    // MARK: Lock skips

    func testALockSkippedPassPostsNothingInAnyMode() {
        // Nothing happened, and on a machine running both the menu bar app and
        // a launchd agent this is the common case, not an event — it would
        // banner every interval to report that nothing occurred.
        let skipped = PassOutcome(disposition: .skippedLocked, result: nil, diagnostics: nil)
        for mode in NotifyMode.allCases {
            XCTAssertNil(
                NotificationPolicy.notification(for: skipped, mode: mode),
                "\(mode.rawValue) should stay silent for a lock skip"
            )
        }
    }

    // MARK: Sound

    func testOnlyErrorsAreWorthASound() throws {
        let quiet = try XCTUnwrap(NotificationPolicy.notification(for: completed(created: 1), mode: .always))
        XCTAssertFalse(quiet.isError, "a routine pass must not chime")
    }
}

/// Escaping is the whole of the fallback path's correctness: get it wrong and
/// the script fails to compile, so the notification silently never appears.
final class AppleScriptStringTests: XCTestCase {
    func testQuotesAreEscaped() {
        XCTAssertEqual(AppleScriptString.escaped("say \"hi\""), "say \\\"hi\\\"")
    }

    func testBackslashesAreEscapedBeforeQuotes() {
        // Order matters and is the classic bug: escaping quotes first, then
        // backslashes, re-escapes the backslashes just inserted, producing a
        // script that does not compile.
        XCTAssertEqual(AppleScriptString.escaped("a\\b"), "a\\\\b")
        XCTAssertEqual(
            AppleScriptString.escaped("a\\\"b"), "a\\\\\\\"b",
            "a backslash followed by a quote is where the wrong order shows"
        )
    }

    func testNewlinesAreFlattened() {
        // A literal newline terminates the AppleScript statement, so a
        // multi-line error message would truncate the script mid-command.
        XCTAssertEqual(AppleScriptString.escaped("line1\nline2"), "line1 line2")
        XCTAssertFalse(AppleScriptString.escaped("a\r\nb").contains("\n"))
    }

    func testAPlainStringIsUntouched() {
        XCTAssertEqual(AppleScriptString.escaped("created=1 updated=0"), "created=1 updated=0")
    }

    func testARealisticErrorMessageSurvives() {
        // The actual shape of a resolution error, which contains quotes.
        let message = "Calendar \"Personal\" not found in account \"iCloud\""
        let escaped = AppleScriptString.escaped(message)
        XCTAssertFalse(escaped.contains("\"") && !escaped.contains("\\\""), "every quote must be escaped")
        // And it round-trips: unescaping gives the original back.
        let unescaped = escaped
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
        XCTAssertEqual(unescaped, message)
    }
}
