import XCTest
@testable import WorkSyncCore

/// Row identity for the settings form's filter lists. The bug these exist for
/// is silent: a commit that arrives after its row moved used to pass the range
/// check and rewrite whatever had shifted into that position.
final class TitleFilterRowsTests: XCTestCase {
    private var handles = SourceHandles()
    private lazy var personal = handles.mint("personal")
    private lazy var list = TitleFilterRowIDs.List(source: personal, field: "matches")
    private lazy var other = TitleFilterRowIDs.List(source: personal, field: "excludes")

    private func seeded(_ entries: [String]) -> TitleFilterRowIDs {
        var ids = TitleFilterRowIDs()
        ids.seed(list, count: entries.count)
        return ids
    }

    func testSeededRowsCarryStableIdentities() {
        let ids = seeded(["a", "b", "c"])
        let first = ids.rows(list, entries: ["a", "b", "c"])
        let second = ids.rows(list, entries: ["a", "b", "c"])
        XCTAssertEqual(first.map(\.id), second.map(\.id), "identity must not change between renders")
        XCTAssertEqual(first.map(\.text), ["a", "b", "c"])
        XCTAssertEqual(Set(first.map(\.id)).count, 3, "each row needs its own")
    }

    func testReseedingALiveListLeavesItsIdentitiesAlone() {
        var ids = seeded(["a", "b"])
        let before = ids.rows(list, entries: ["a", "b"]).map(\.id)
        ids.seed(list, count: 2)
        XCTAssertEqual(ids.rows(list, entries: ["a", "b"]).map(\.id), before)
    }

    func testAnUnseededListFallsBackToPositions() {
        // No worse than the behaviour that existed before identity, and stable
        // across renders, which is what SwiftUI needs from a ForEach key.
        let ids = TitleFilterRowIDs()
        XCTAssertEqual(ids.rows(list, entries: ["a", "b"]).map(\.id), [.position(0), .position(1)])
    }

    func testListsAreIndependent() {
        var ids = seeded(["a"])
        ids.seed(other, count: 1)
        XCTAssertNotEqual(
            ids.rows(list, entries: ["a"]).first?.id,
            ids.rows(other, entries: ["a"]).first?.id,
            "the same text in the two lists is still two different rows"
        )
    }

    // MARK: The defect

    /// `[A, B, C]`, remove row 0, then B's still-live field commits. By
    /// position it would write to index 1, which is now C. By identity it
    /// writes to B, wherever B ended up.
    func testACommitAfterARemovalResolvesToItsOwnRow() {
        var ids = seeded(["A", "B", "C"])
        let rows = ids.rows(list, entries: ["A", "B", "C"])
        let bID = rows[1].id

        ids.removed(at: 0, from: list)
        let entries = ["B", "C"]

        XCTAssertEqual(
            ids.position(of: bID, in: list, count: entries.count), 0,
            "B moved to index 0, and its late commit must follow it — not land on C at index 1"
        )
    }

    func testACommitForARemovedRowResolvesToNothing() {
        var ids = seeded(["A", "B", "C"])
        let aID = ids.rows(list, entries: ["A", "B", "C"])[0].id

        ids.removed(at: 0, from: list)
        XCTAssertNil(
            ids.position(of: aID, in: list, count: 2),
            "the row is gone, so its commit must be dropped rather than applied to a neighbour"
        )
    }

    /// The reason rows cannot be keyed by their text: while one is being typed
    /// the two can read the same, and they are still two rows.
    func testTwoRowsWithIdenticalTextAreStillTwoRows() {
        var ids = seeded(["B", "B"])
        let rows = ids.rows(list, entries: ["B", "B"])
        XCTAssertNotEqual(rows[0].id, rows[1].id)
        XCTAssertEqual(ids.position(of: rows[0].id, in: list, count: 2), 0)
        XCTAssertEqual(ids.position(of: rows[1].id, in: list, count: 2), 1)

        // Remove the first: the second keeps its own identity and moves up.
        ids.removed(at: 0, from: list)
        XCTAssertNil(ids.position(of: rows[0].id, in: list, count: 1))
        XCTAssertEqual(ids.position(of: rows[1].id, in: list, count: 1), 0)
    }

    func testAppendingGivesTheNewRowItsOwnIdentity() {
        var ids = seeded(["a"])
        let first = ids.rows(list, entries: ["a"])[0].id
        ids.appended(to: list)
        let rows = ids.rows(list, entries: ["a", "b"])
        XCTAssertEqual(rows[0].id, first, "the existing row keeps its identity")
        XCTAssertNotEqual(rows[1].id, first)
    }

    func testARemovalOutOfRangeChangesNothing() {
        var ids = seeded(["a", "b"])
        let before = ids.rows(list, entries: ["a", "b"]).map(\.id)
        ids.removed(at: 7, from: list)
        ids.removed(at: -1, from: list)
        XCTAssertEqual(ids.rows(list, entries: ["a", "b"]).map(\.id), before)
    }

    func testPositionsAreBoundedByTheLiveCount() {
        // The identities say index 2, but the list the caller holds has shrunk.
        var ids = seeded(["a", "b", "c"])
        let third = ids.rows(list, entries: ["a", "b", "c"])[2].id
        XCTAssertNil(ids.position(of: third, in: list, count: 2))
        XCTAssertNil(ids.position(of: .position(5), in: list, count: 2))
    }

    // MARK: Following the source

    /// Rows are keyed by the source's identity, and a rename moves only the id,
    /// so there is nothing to re-key: the live text fields keep reading the
    /// same rows.
    func testRenamingASourceKeepsItsRowIdentities() {
        var ids = seeded(["a", "b"])
        let before = ids.rows(list, entries: ["a", "b"]).map(\.id)
        handles.rename(personal, to: "home")
        XCTAssertEqual(handles.id(of: personal), "home")
        XCTAssertEqual(ids.rows(list, entries: ["a", "b"]).map(\.id), before)
    }

    func testRemovingASourceDropsItsLists() {
        var ids = seeded(["a"])
        ids.seed(other, count: 1)
        ids.removeSource(personal)
        XCTAssertEqual(ids.rows(list, entries: ["a"]).map(\.id), [.position(0)])
        XCTAssertEqual(ids.rows(other, entries: ["a"]).map(\.id), [.position(0)])
    }

    func testRemoveAllDropsEverything() {
        var ids = seeded(["a", "b"])
        ids.removeAll()
        XCTAssertEqual(ids.rows(list, entries: ["a", "b"]).map(\.id), [.position(0), .position(1)])
    }
}
