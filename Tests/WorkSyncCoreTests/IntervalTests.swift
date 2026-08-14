import XCTest
@testable import WorkSyncCore

final class IntervalTests: XCTestCase {
    private func date(_ minutes: Int) -> Date {
        Date(timeIntervalSince1970: Double(minutes) * 60)
    }

    private func interval(_ startMin: Int, _ endMin: Int) -> Interval {
        Interval(start: date(startMin), end: date(endMin))
    }

    func testOverlapHalfOpen() {
        XCTAssertTrue(interval(0, 60).overlaps(interval(30, 90)))
        XCTAssertFalse(interval(0, 60).overlaps(interval(60, 90)), "touching endpoints do not overlap (half-open)")
        XCTAssertFalse(interval(0, 60).overlaps(interval(90, 120)))
    }

    func testPadding() {
        let padded = interval(120, 180).padded(beforeMinutes: 120, afterMinutes: 60)
        XCTAssertEqual(padded, interval(0, 240))
    }

    func testCoalesceMergesWithinGap() {
        let merged = IntervalMath.coalesce([interval(0, 60), interval(70, 120)], gapMinutes: 15)
        XCTAssertEqual(merged, [interval(0, 120)])
    }

    func testCoalesceRespectsGapBoundary() {
        // Gap of exactly 15 minutes merges; 16 does not.
        XCTAssertEqual(IntervalMath.coalesce([interval(0, 60), interval(75, 120)], gapMinutes: 15).count, 1)
        XCTAssertEqual(IntervalMath.coalesce([interval(0, 60), interval(76, 120)], gapMinutes: 15).count, 2)
    }

    func testCoalesceHandlesNestedAndUnsorted() {
        let merged = IntervalMath.coalesce(
            [interval(30, 40), interval(0, 100), interval(50, 60)], gapMinutes: 0
        )
        XCTAssertEqual(merged, [interval(0, 100)])
    }

    func testUnionDurationDoubleBookedNotDoubleCounted() {
        // Block 0–100. Two fully overlapping busy meetings 0–60 each, plus 60–70.
        // Naive summing: 60+60+10 = 130 → 130% coverage. Union: 70 → 70%.
        let block = interval(0, 100)
        let busy = [interval(0, 60), interval(0, 60), interval(60, 70)]
        let union = IntervalMath.unionDuration(of: busy, clippedTo: block)
        XCTAssertEqual(union, 70 * 60, accuracy: 0.001)
        XCTAssertLessThan(union / block.duration, 0.8, "double-booked time must not push coverage over the threshold")
    }

    func testUnionDurationClipsToBounds() {
        let block = interval(50, 100)
        let busy = [interval(0, 70)] // only 50–70 lies inside the block
        XCTAssertEqual(IntervalMath.unionDuration(of: busy, clippedTo: block), 20 * 60, accuracy: 0.001)
    }
}
