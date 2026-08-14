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

/// One managed event discovered by a purge sweep.
public struct FoundManagedEvent: Equatable, Sendable {
    public let eventIdentifier: String
    public let title: String
    public let marker: Marker
    public let calendarTitle: String
    public let accountTitle: String
}

public struct PurgeScanResult: Equatable, Sendable {
    public var found: [FoundManagedEvent] = []
    /// Calendars that could not be read. A sweep that skipped a calendar has
    /// NOT proven the absence of managed events, so this must reach the exit
    /// code — "no managed events found" after a failed scan is a lie.
    public var scanFailures: [String] = []

    public var isComplete: Bool {
        scanFailures.isEmpty
    }

    public var countsBySource: [String: Int] {
        found.reduce(into: [:]) { counts, event in
            counts[event.marker.sourceID, default: 0] += 1
        }
    }
}

public struct PurgeDeleteResult: Equatable, Sendable {
    public var deleted = 0
    public var failures: [String] = []
}

/// The purge sweep, in the core so its failure signalling is unit-testable
/// against the in-memory store rather than only reachable through the CLI.
public enum PurgeEngine {
    /// Discovery across every calendar on every account — deliberately not
    /// bound to the sync window, so it also collects events stranded by a
    /// since-changed config (SPEC §8).
    public static func scan(
        store: CalendarStore,
        now: Date,
        sourceFilter: String?
    ) -> PurgeScanResult {
        var result = PurgeScanResult()
        let span = PurgeScan.span(around: now)

        let calendars: [CalendarRef]
        do {
            calendars = try store.calendars()
        } catch {
            result.scanFailures.append("could not list calendars: \(error.localizedDescription)")
            return result
        }

        for calendar in calendars {
            let events: [StoredEvent]
            do {
                events = try store.events(in: calendar, from: span.start, to: span.end)
            } catch {
                // One unreadable calendar must not abort the sweep, but it must
                // not be forgotten either.
                result.scanFailures.append(
                    "\(calendar.accountTitle)/\(calendar.title): \(error.localizedDescription)"
                )
                continue
            }
            for event in events {
                guard let marker = PurgeScan.claimable(event, sourceFilter: sourceFilter) else { continue }
                result.found.append(FoundManagedEvent(
                    eventIdentifier: event.eventIdentifier,
                    title: event.title,
                    marker: marker,
                    calendarTitle: calendar.title,
                    accountTitle: calendar.accountTitle
                ))
            }
        }
        return result
    }

    /// Deletes discovered events, continuing past individual failures.
    public static func delete(_ found: [FoundManagedEvent], store: CalendarStore) -> PurgeDeleteResult {
        var result = PurgeDeleteResult()
        for event in found {
            do {
                try store.delete(eventIdentifier: event.eventIdentifier)
                result.deleted += 1
            } catch {
                result.failures.append("\"\(event.title)\": \(error.localizedDescription)")
            }
        }
        do {
            try store.commit()
        } catch {
            result.failures.append("commit failed: \(error.localizedDescription)")
        }
        return result
    }
}
