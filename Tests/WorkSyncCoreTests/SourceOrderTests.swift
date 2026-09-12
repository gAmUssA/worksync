import XCTest
@testable import WorkSyncCore

/// Reordering the source list. Order decides cross-source dedup (SPEC §5 step
/// 5), so reordering the wrong source is a semantic change, not a cosmetic one:
/// a different source starts supplying a shared event's blocker.
final class SourceOrderTests: XCTestCase {
    private var handles = SourceHandles()

    /// `[A, B, C, D]` as the list looked when the drag started.
    private lazy var rendered: [SourceHandle] = ["A", "B", "C", "D"].map { handles.mint($0) }

    private func order(_ names: [String]) -> [SourceHandle] {
        _ = rendered // the handles are minted there
        return names.compactMap { handles.handle(of: $0) }
    }

    // MARK: A drag against the list it was drawn on

    func testAnOrdinaryMoveFits() {
        XCTAssertTrue(SourceOrder.canMove(
            fromOffsets: IndexSet(integer: 1), toOffset: 3, rendered: rendered, current: rendered
        ))
        XCTAssertTrue(SourceOrder.canMove(
            fromOffsets: IndexSet(integer: 3), toOffset: 0, rendered: rendered, current: rendered
        ))
    }

    func testDroppingPastTheLastRowFits() {
        // A drop below everything arrives as destination == count.
        XCTAssertTrue(SourceOrder.canMove(
            fromOffsets: IndexSet(integer: 0), toOffset: 4, rendered: rendered, current: rendered
        ))
    }

    func testAMultipleSelectionFits() {
        XCTAssertTrue(SourceOrder.canMove(
            fromOffsets: IndexSet([0, 2]), toOffset: 4, rendered: rendered, current: rendered
        ))
    }

    // MARK: A drag against a list that changed under it

    /// The defect: `A` is removed while the user is dragging `B` from 1 to 3.
    /// The offsets still fit `[B, C, D]` — and name `C`, which nobody dragged.
    func testADropOntoAListThatLostASourceIsRejected() {
        let current = order(["B", "C", "D"])
        // Both halves of the old guard still pass, which is exactly why range
        // was not enough: offset 1 of [B, C, D] is C.
        XCTAssertTrue(current.indices.contains(1), "the dragged offset still names a row")
        XCTAssertTrue((0 ... current.count).contains(3), "and the destination is still somewhere to drop")
        XCTAssertFalse(SourceOrder.canMove(
            fromOffsets: IndexSet(integer: 1), toOffset: 3, rendered: rendered, current: current
        ))
    }

    func testAMultiSelectDragIsRejectedWholeWhenOneRowIsGone() {
        // Dragging B and D; C disappears between the drag and the drop.
        let current = order(["A", "B", "D"])
        XCTAssertFalse(SourceOrder.canMove(
            fromOffsets: IndexSet([1, 3]), toOffset: 0, rendered: rendered, current: current
        ))
    }

    func testADropOntoAListThatGainedASourceIsRejected() {
        var current = rendered
        current.append(handles.mint("E"))
        XCTAssertFalse(SourceOrder.canMove(
            fromOffsets: IndexSet(integer: 0), toOffset: 2, rendered: rendered, current: current
        ))
    }

    /// Same sources, already reordered by something else since the drag began.
    func testADropOntoAReorderedListIsRejected() {
        let current = order(["B", "A", "C", "D"])
        XCTAssertFalse(SourceOrder.canMove(
            fromOffsets: IndexSet(integer: 0), toOffset: 2, rendered: rendered, current: current
        ))
    }

    /// Identity, not name: a source removed and replaced by one that took its
    /// id is a different row.
    func testADropIsRejectedWhenASourceWasReplacedByItsNamesake() {
        var replaced = rendered
        handles.remove(rendered[0])
        replaced[0] = handles.mint("A")
        XCTAssertFalse(SourceOrder.canMove(
            fromOffsets: IndexSet(integer: 0), toOffset: 2, rendered: rendered, current: replaced
        ))
    }

    // MARK: The in-range guard, kept

    func testAnOffsetPastTheEndDoesNotFit() {
        XCTAssertFalse(SourceOrder.canMove(
            fromOffsets: IndexSet(integer: 9), toOffset: 0, rendered: rendered, current: rendered
        ))
        XCTAssertFalse(SourceOrder.canMove(
            fromOffsets: IndexSet([0, 5]), toOffset: 0, rendered: rendered, current: rendered
        ))
    }

    func testADestinationPastTheEndDoesNotFit() {
        XCTAssertFalse(SourceOrder.canMove(
            fromOffsets: IndexSet(integer: 0), toOffset: 5, rendered: rendered, current: rendered
        ))
        XCTAssertFalse(SourceOrder.canMove(
            fromOffsets: IndexSet(integer: 0), toOffset: -1, rendered: rendered, current: rendered
        ))
    }

    func testAnEmptyMoveDoesNotFit() {
        XCTAssertFalse(SourceOrder.canMove(
            fromOffsets: IndexSet(), toOffset: 0, rendered: rendered, current: rendered
        ))
    }

    func testNothingFitsAnEmptyList() {
        XCTAssertFalse(SourceOrder.canMove(
            fromOffsets: IndexSet(integer: 0), toOffset: 0, rendered: [], current: []
        ))
    }
}
