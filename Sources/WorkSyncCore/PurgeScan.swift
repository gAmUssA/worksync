import Foundation

/// The pure decisions behind `worksync purge` (SPEC §8), split out so the
/// span bound and the claim rule are unit-tested rather than trusted.
public enum PurgeScan {
    /// Days scanned in each direction from now.
    public static let radiusDays = 365.0

    /// The bounded span purge queries.
    ///
    /// This bound is mandatory, not a performance nicety.
    /// `EKEventStore.predicateForEvents` matches at most a four-year span and
    /// silently shortens anything wider to the first four years — no error, no
    /// flag. A naive "all of time" query therefore returns a plausible-looking
    /// result set that quietly ends four years in, so purge would report
    /// success while leaving every newer managed event in place. 365 days each
    /// way covers any realistic backlog and stays far under the limit.
    public static func span(around now: Date) -> Interval {
        Interval(
            start: now.addingTimeInterval(-radiusDays * 86400),
            end: now.addingTimeInterval(radiusDays * 86400)
        )
    }

    /// Returns the marker if this event is ours and in scope for the purge.
    ///
    /// Only current-version markers are ever returned: an event written by a
    /// future version must be left untouched rather than deleted by an older
    /// binary that cannot understand it (SPEC §7).
    public static func claimable(_ event: StoredEvent, sourceFilter: String?) -> Marker? {
        guard let marker = Marker.extract(url: event.url, notes: event.notes),
              marker.isCurrentVersion
        else { return nil }
        if let sourceFilter, marker.sourceID != sourceFilter {
            return nil
        }
        return marker
    }
}
