import XCTest
@testable import WorkSyncCore

/// A source's identity while the settings form is open. Three rounds of this PR
/// approximated it — integer index, then config id, then config id again — and
/// each approximation left a hole, because an id is data the user can edit.
final class SourceHandlesTests: XCTestCase {
    func testSeedingGivesEverySourceItsOwnIdentity() throws {
        var handles = SourceHandles()
        handles.seed(["personal", "travel"])

        let personal = try XCTUnwrap(handles.handle(of: "personal"))
        let travel = try XCTUnwrap(handles.handle(of: "travel"))
        XCTAssertNotEqual(personal, travel)
        XCTAssertEqual(handles.id(of: personal), "personal")
        XCTAssertEqual(handles.id(of: travel), "travel")
    }

    func testSeedingRetiresTheIdentitiesOfTheSessionBefore() throws {
        // Reopening the form is a new editing session: a control left holding a
        // handle from the last one must not resolve.
        var handles = SourceHandles()
        handles.seed(["personal"])
        let old = try XCTUnwrap(handles.handle(of: "personal"))

        handles.seed(["personal"])
        XCTAssertNil(handles.id(of: old))
        XCTAssertNotNil(handles.handle(of: "personal"))
    }

    // MARK: Rename

    func testARenameMovesTheIdAndNotTheIdentity() throws {
        var handles = SourceHandles()
        handles.seed(["personal"])
        let personal = try XCTUnwrap(handles.handle(of: "personal"))

        handles.rename(personal, to: "home")
        XCTAssertEqual(handles.id(of: personal), "home", "the same handle, now naming the new id")
        XCTAssertEqual(handles.handle(of: "home"), personal)
        XCTAssertNil(handles.handle(of: "personal"))
    }

    /// The defect a config id left: a control built before the rename commits
    /// with the id it captured. A handle captured before the rename still names
    /// the same source afterwards, so nothing has to be re-keyed and nothing
    /// can be re-keyed wrongly.
    func testAHandleCapturedBeforeARenameStillNamesItsSource() throws {
        var handles = SourceHandles()
        handles.seed(["personal"])
        let captured = try XCTUnwrap(handles.handle(of: "personal"))

        handles.rename(captured, to: "home")
        XCTAssertEqual(handles.resolve(captured)?.id, "home")
    }

    func testRenamingARetiredHandleDoesNothing() throws {
        var handles = SourceHandles()
        handles.seed(["personal"])
        let personal = try XCTUnwrap(handles.handle(of: "personal"))
        handles.remove(personal)

        handles.rename(personal, to: "home")
        XCTAssertNil(handles.id(of: personal))
        XCTAssertNil(handles.handle(of: "home"), "a dead handle must not resurrect itself under a new id")
    }

    // MARK: Removal and id reuse

    func testARemovedSourcesHandleResolvesToNothing() throws {
        var handles = SourceHandles()
        handles.seed(["personal", "travel"])
        let personal = try XCTUnwrap(handles.handle(of: "personal"))

        handles.remove(personal)
        XCTAssertNil(handles.id(of: personal))
        XCTAssertNil(handles.resolve(personal))
        XCTAssertNotNil(handles.handle(of: "travel"), "the other source is untouched")
    }

    /// The second hole: a removed source's id can be taken by a new one. A
    /// stale control must resolve to nothing, never to the replacement.
    func testAStaleHandleDoesNotResolveToASourceThatReusedItsID() throws {
        var handles = SourceHandles()
        handles.seed(["personal"])
        let removed = try XCTUnwrap(handles.handle(of: "personal"))
        handles.remove(removed)

        // A new source is created and renamed to the id that just came free.
        let replacement = handles.mint("source-2")
        handles.rename(replacement, to: "personal")

        XCTAssertNil(handles.id(of: removed), "the old handle names nothing, id reuse or not")
        XCTAssertNotEqual(removed, replacement)
        XCTAssertEqual(handles.id(of: replacement), "personal")
        XCTAssertEqual(handles.handle(of: "personal"), replacement)
    }

    func testResolveIsNilForNoSelection() {
        let handles = SourceHandles()
        XCTAssertNil(handles.resolve(nil))
    }

    func testMintingGivesANewSourceItsOwnIdentity() {
        var handles = SourceHandles()
        handles.seed(["personal"])
        let added = handles.mint("source-2")
        XCTAssertNotEqual(added, handles.handle(of: "personal"))
        XCTAssertEqual(handles.id(of: added), "source-2")
    }

    func testRemoveAllRetiresEverything() throws {
        var handles = SourceHandles()
        handles.seed(["personal", "travel"])
        let personal = try XCTUnwrap(handles.handle(of: "personal"))
        handles.removeAll()
        XCTAssertNil(handles.id(of: personal))
        XCTAssertNil(handles.handle(of: "travel"))
    }
}
