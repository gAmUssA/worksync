import Foundation

/// The identity of one concrete event occurrence.
///
/// The tuple, never the identifier alone: every occurrence of a recurring
/// series shares one `calendarItemExternalIdentifier`, so keying on it by
/// itself would make a single source's 2nd, 3rd, … occurrences look like
/// duplicates of its first and silently drop them — which would then delete
/// already-synced blockers. `occurrenceDate` rather than the current start date
/// keeps identity stable when a detached occurrence is dragged to a new time
/// (SPEC §5 step 5).
public struct EventIdentity: Hashable, Sendable {
    public let externalIdentifier: String
    public let occurrenceDate: Date

    public init(_ event: StoredEvent) {
        externalIdentifier = event.externalIdentifier
        occurrenceDate = event.occurrenceDate
    }
}

/// One source's contribution to a pass.
public struct SourcePlanInput: Sendable {
    public let source: SourceConfig
    public let targetCalendar: CalendarRef
    public let events: [StoredEvent]

    public init(source: SourceConfig, targetCalendar: CalendarRef, events: [StoredEvent]) {
        self.source = source
        self.targetCalendar = targetCalendar
        self.events = events
    }
}

public struct MultiSourceResult: Sendable {
    public var blocks: [DesiredBlock] = []
    /// Per source id, how many of its events were already claimed by an
    /// earlier-listed source. Reported rather than swallowed: a surprising
    /// count here is usually the first sign that two sources overlap more than
    /// the user thought.
    public var duplicatesDropped: [String: Int] = [:]

    public var totalDuplicatesDropped: Int {
        duplicatesDropped.values.reduce(0, +)
    }
}

public struct ConflictSkipResult: Sendable {
    public var kept: [DesiredBlock] = []
    public var skipped: Int = 0
    /// Per source id, how many of its blocks were skipped as already-busy.
    public var skippedBySource: [String: Int] = [:]
}

public extension SyncPlanner {
    /// SPEC §5 steps 3–5: filter each source, resolve cross-source duplicates in
    /// config order, then transform what survives.
    ///
    /// Order is load-bearing, not cosmetic: the first-listed source wins, so
    /// reordering `[[source]]` blocks silently changes which source's title,
    /// padding, and target calendar a shared event gets (SPEC §4.1). That is
    /// why the config writer must preserve source order exactly.
    static func desiredAcrossSources(
        _ inputs: [SourcePlanInput],
        window: Interval,
        calendar: Calendar = .current
    ) -> MultiSourceResult {
        var result = MultiSourceResult()
        var claimed = Set<EventIdentity>()

        for input in inputs {
            // Step 3 first: only an event this source would actually mirror is
            // allowed to claim an identity.
            let eligible = SyncPlanner.eligible(input.events, for: input.source)

            var unclaimed: [StoredEvent] = []
            var dropped = 0
            for event in eligible {
                // insert() returns false when an earlier source already claimed
                // this occurrence, which is exactly the first-wins rule.
                if claimed.insert(EventIdentity(event)).inserted {
                    unclaimed.append(event)
                } else {
                    dropped += 1
                }
            }
            if dropped > 0 {
                result.duplicatesDropped[input.source.id] = dropped
            }

            // Step 4 runs on the deduped set, so coalescing never merges an
            // event that belongs to another source.
            result.blocks += SyncPlanner.blocks(
                source: input.source,
                targetCalendar: input.targetCalendar,
                eligibleEvents: unclaimed,
                window: window,
                calendar: calendar
            )
        }
        return result
    }

    /// SPEC §5 step 7: drop blocks whose time is already covered by real work
    /// events, for sources that asked for it via `skip_if_work_busy`.
    ///
    /// Coverage is the UNION of the busy intervals, never the sum of their
    /// durations. Work calendars routinely contain double-booked and nested
    /// meetings, and summing would double-count that time and push a barely
    /// covered block over the threshold.
    ///
    /// `existingOnTargets` is the same fetch reconciliation uses (step 6) — no
    /// second round trip to the calendar store.
    static func applyConflictSkips(
        to desired: [DesiredBlock],
        existingOnTargets: [StoredEvent],
        sources: [SourceConfig],
        threshold: Double = 0.8
    ) -> ConflictSkipResult {
        let configByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })

        // Anything carrying a marker of any version is one of ours and must not
        // count as a conflict against itself. A future-version marker still
        // means "worksync wrote this", so it is excluded too.
        let realWorkEvents = existingOnTargets.filter { event in
            guard Marker.extract(url: event.url, notes: event.notes) == nil else { return false }
            // A meeting the user declined, or one explicitly marked Free, is not
            // busy time and must not suppress a blocker.
            if event.isDeclinedByUser {
                return false
            }
            if event.availability == .free {
                return false
            }
            return true
        }

        var result = ConflictSkipResult()
        for block in desired {
            guard configByID[block.sourceID]?.skipIfWorkBusy == true else {
                result.kept.append(block)
                continue
            }
            guard block.interval.duration > 0 else {
                result.kept.append(block)
                continue
            }

            let busy = realWorkEvents
                .filter { $0.calendarId == block.calendarId }
                .map { Interval(start: $0.start, end: $0.end) }
                .filter { $0.overlaps(block.interval) }

            let covered = IntervalMath.unionDuration(of: busy, clippedTo: block.interval)
            if covered / block.interval.duration >= threshold {
                result.skipped += 1
                result.skippedBySource[block.sourceID, default: 0] += 1
            } else {
                result.kept.append(block)
            }
        }
        return result
    }
}
