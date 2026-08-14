import Foundation

/// A half-open time interval [start, end).
public struct Interval: Hashable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public func overlaps(_ other: Interval) -> Bool {
        start < other.end && other.start < end
    }

    /// Clips this interval to the given bounds; nil if no overlap.
    public func clipped(to bounds: Interval) -> Interval? {
        let s = max(start, bounds.start)
        let e = min(end, bounds.end)
        guard s < e else { return nil }
        return Interval(start: s, end: e)
    }

    public func padded(beforeMinutes: Int, afterMinutes: Int) -> Interval {
        Interval(
            start: start.addingTimeInterval(-Double(beforeMinutes) * 60),
            end: end.addingTimeInterval(Double(afterMinutes) * 60)
        )
    }
}

public enum IntervalMath {
    /// Merges intervals whose gap is <= gapMinutes. Input order does not matter.
    /// Returns merged intervals sorted by start.
    public static func coalesce(_ intervals: [Interval], gapMinutes: Int) -> [Interval] {
        guard !intervals.isEmpty else { return [] }
        let gap = Double(gapMinutes) * 60
        let sorted = intervals.sorted { $0.start < $1.start }
        var result: [Interval] = [sorted[0]]
        for interval in sorted.dropFirst() {
            var last = result[result.count - 1]
            if interval.start.timeIntervalSince(last.end) <= gap {
                last.end = max(last.end, interval.end)
                result[result.count - 1] = last
            } else {
                result.append(interval)
            }
        }
        return result
    }

    /// Union length of intervals clipped to bounds (zero-gap coalescing of clipped spans).
    /// Correct for double-booked/nested busy events, where naive summing double-counts.
    public static func unionDuration(of intervals: [Interval], clippedTo bounds: Interval) -> TimeInterval {
        let clipped = intervals.compactMap { $0.clipped(to: bounds) }
        return coalesce(clipped, gapMinutes: 0).reduce(0) { $0 + $1.duration }
    }
}
