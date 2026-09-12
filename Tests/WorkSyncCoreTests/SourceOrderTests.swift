import XCTest
@testable import WorkSyncCore

/// Reordering the source list. Order decides cross-source dedup (SPEC §4.1), so
/// a drop either fits the list it lands on or is ignored — applying offsets from
/// a list that has since shrunk traps rather than reordering wrongly.
final class SourceOrderTests: XCTestCase {
    private func sources(_ count: Int) -> [SourceConfig] {
        (0 ..< count).map { SourceConfig(id: "s\($0)", account: "iCloud", calendar: "C") }
    }

    func testAnOrdinaryMoveFits() {
        XCTAssertTrue(SourceOrder.canMove(sources(3), fromOffsets: IndexSet(integer: 0), toOffset: 2))
        XCTAssertTrue(SourceOrder.canMove(sources(3), fromOffsets: IndexSet(integer: 2), toOffset: 0))
    }

    func testDroppingPastTheLastRowFits() {
        // A drop below everything arrives as destination == count.
        XCTAssertTrue(SourceOrder.canMove(sources(2), fromOffsets: IndexSet(integer: 0), toOffset: 2))
    }

    func testAMultipleSelectionFits() {
        XCTAssertTrue(SourceOrder.canMove(sources(4), fromOffsets: IndexSet([0, 2]), toOffset: 4))
    }

    /// The stale drop: the list lost a source between the drag and the drop.
    func testAnOffsetPastTheEndDoesNotFit() {
        XCTAssertFalse(SourceOrder.canMove(sources(2), fromOffsets: IndexSet(integer: 2), toOffset: 0))
        XCTAssertFalse(SourceOrder.canMove(sources(2), fromOffsets: IndexSet([0, 5]), toOffset: 0))
    }

    func testADestinationPastTheEndDoesNotFit() {
        XCTAssertFalse(SourceOrder.canMove(sources(2), fromOffsets: IndexSet(integer: 0), toOffset: 3))
        XCTAssertFalse(SourceOrder.canMove(sources(2), fromOffsets: IndexSet(integer: 0), toOffset: -1))
    }

    func testAnEmptyMoveDoesNotFit() {
        XCTAssertFalse(SourceOrder.canMove(sources(2), fromOffsets: IndexSet(), toOffset: 0))
    }

    func testNothingFitsAnEmptyList() {
        XCTAssertFalse(SourceOrder.canMove([], fromOffsets: IndexSet(integer: 0), toOffset: 0))
    }
}
