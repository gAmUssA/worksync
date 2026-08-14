import Foundation

/// A blocker event as it should exist on the work calendar.
public struct DesiredBlock: Equatable, Sendable {
    public let sourceID: String
    public let calendarId: String
    public let title: String
    public let interval: Interval
    public let isAllDay: Bool
    public let availability: Availability
    public let marker: Marker

    public init(
        sourceID: String, calendarId: String, title: String,
        interval: Interval, isAllDay: Bool, availability: Availability, marker: Marker
    ) {
        self.sourceID = sourceID
        self.calendarId = calendarId
        self.title = title
        self.interval = interval
        self.isAllDay = isAllDay
        self.availability = availability
        self.marker = marker
    }
}

/// One planned mutation against the calendar store.
public enum PlannedChange: Equatable, Sendable {
    case create(DesiredBlock)
    /// Update the existing event (by eventIdentifier) in place to match desired.
    case update(eventIdentifier: String, DesiredBlock)
    case delete(eventIdentifier: String, marker: Marker, title: String)
}

public struct SyncPlan: Equatable, Sendable {
    public var changes: [PlannedChange] = []
    public var unchangedCount: Int = 0
    public var skippedCount: Int = 0

    public var createCount: Int {
        changes.filter {
            if case .create = $0 {
                true
            } else {
                false
            }
        }.count
    }

    public var updateCount: Int {
        changes.filter {
            if case .update = $0 {
                true
            } else {
                false
            }
        }.count
    }

    public var deleteCount: Int {
        changes.filter {
            if case .delete = $0 {
                true
            } else {
                false
            }
        }.count
    }

    /// The one-line summary used by logs, the menu bar header, and notifications.
    public var summaryLine: String {
        "created=\(createCount) updated=\(updateCount) deleted=\(deleteCount) skipped=\(skippedCount) unchanged=\(unchangedCount)"
    }
}

public enum SyncPlanner {
    /// The rolling sync window: [now - 1h, now + windowDays].
    public static func window(now: Date, windowDays: Int) -> Interval {
        Interval(
            start: now.addingTimeInterval(-3600),
            end: now.addingTimeInterval(Double(windowDays) * 86400)
        )
    }

    /// Computes the desired blocker set for one source (SPEC §5 steps 3–4).
    /// Filters, pads, coalesces, then window-FILTERS (never clamps — clamping to a
    /// rolling window breaks reconciliation convergence).
    public static func desiredBlocks(
        source: SourceConfig,
        targetCalendar: CalendarRef,
        events: [StoredEvent],
        window: Interval,
        calendar: Calendar = .current
    ) -> [DesiredBlock] {
        blocks(
            source: source,
            targetCalendar: targetCalendar,
            eligibleEvents: eligible(events, for: source, calendar: calendar),
            window: window,
            calendar: calendar
        )
    }

    /// SPEC §5 step 3: the per-source eligibility filters, separated from the
    /// transform so cross-source dedup can run between them (step 5). Dedup has
    /// to see exactly the events a source would actually mirror: an event a
    /// source filters out must never claim an identity and thereby block a
    /// later source from producing it.
    public static func eligible(
        _ events: [StoredEvent],
        for source: SourceConfig,
        calendar: Calendar = .current
    ) -> [StoredEvent] {
        events.filter { event in
            // No usable identity means no stable marker key: two such events
            // would hash to the same key and silently collapse into one entry
            // in reconcile()'s desired map, dropping a blocker with no trace.
            // Skip them instead; callers report the count via unidentifiable(_:).
            if event.externalIdentifier.isEmpty {
                return false
            }
            if event.isDeclinedByUser {
                return false
            }
            if event.availability == .free {
                return false
            }
            if event.isAllDay, !source.includeAllDay {
                return false
            }
            if !event.isAllDay,
               event.end.timeIntervalSince(event.start) < Double(source.minDurationMinutes) * 60 {
                return false
            }
            // Measured on the raw event, before padding: padding is config that
            // has nothing to do with how long the event really is, and letting
            // it decide eligibility would make the filter depend on unrelated
            // settings. Coalesced clusters are deliberately exempt — a long
            // block built from back-to-back real meetings is honest busy time.
            if !event.isAllDay, source.maxDurationMinutes > 0,
               event.end.timeIntervalSince(event.start) > Double(source.maxDurationMinutes) * 60 {
                return false
            }
            if Weekday.fallsEntirelyOnSkippedDays(
                start: event.start, end: event.end, skip: source.skipWeekdays, calendar: calendar
            ) {
                return false
            }
            return true
        }
    }

    /// SPEC §5 step 4: padding, within-source coalescing, and window filtering.
    /// Assumes `eligibleEvents` has already passed step 3.
    static func blocks(
        source: SourceConfig,
        targetCalendar: CalendarRef,
        eligibleEvents eligible: [StoredEvent],
        window: Interval,
        calendar: Calendar = .current
    ) -> [DesiredBlock] {
        // All-day events become all-day blockers on the same date span; they are
        // never padded or coalesced with timed events.
        let allDay = eligible.filter(\.isAllDay)
        let timed = eligible.filter { !$0.isAllDay }

        var blocks: [DesiredBlock] = []

        for event in allDay {
            let interval = Interval(start: event.start, end: event.end)
            guard interval.overlaps(window) else { continue }
            let marker = Marker(
                sourceID: source.id,
                key: Marker.key(externalIdentifier: event.externalIdentifier, occurrenceDate: event.occurrenceDate)
            )
            blocks.append(DesiredBlock(
                sourceID: source.id,
                calendarId: targetCalendar.id,
                title: renderTitle(source.titleTemplate, eventStart: event.start, calendar: calendar),
                interval: interval,
                isAllDay: true,
                availability: source.availability,
                marker: marker
            ))
        }

        let padded: [(interval: Interval, event: StoredEvent)] = timed.map { event in
            (
                Interval(start: event.start, end: event.end)
                    .padded(beforeMinutes: source.paddingBeforeMinutes, afterMinutes: source.paddingAfterMinutes),
                event
            )
        }

        if source.coalesce {
            // Group into coalesced clusters, tracking constituents for the block key.
            let sorted = padded.sorted { $0.interval.start < $1.interval.start }
            var clusters: [(interval: Interval, members: [StoredEvent])] = []
            let gap = Double(source.coalesceGapMinutes) * 60
            for item in sorted {
                if var last = clusters.last, item.interval.start.timeIntervalSince(last.interval.end) <= gap {
                    last.interval.end = max(last.interval.end, item.interval.end)
                    last.members.append(item.event)
                    clusters[clusters.count - 1] = last
                } else {
                    clusters.append((item.interval, [item.event]))
                }
            }
            for cluster in clusters {
                guard cluster.interval.overlaps(window) else { continue }
                let key: String
                if cluster.members.count == 1 {
                    let e = cluster.members[0]
                    key = Marker.key(externalIdentifier: e.externalIdentifier, occurrenceDate: e.occurrenceDate)
                } else {
                    key = Marker.coalescedKey(
                        constituents: cluster.members.map { ($0.externalIdentifier, $0.occurrenceDate) }
                    )
                }
                blocks.append(DesiredBlock(
                    sourceID: source.id,
                    calendarId: targetCalendar.id,
                    title: renderTitle(source.titleTemplate, eventStart: cluster.members[0].start, calendar: calendar),
                    interval: cluster.interval,
                    isAllDay: false,
                    availability: source.availability,
                    marker: Marker(sourceID: source.id, key: key)
                ))
            }
        } else {
            for item in padded {
                guard item.interval.overlaps(window) else { continue }
                let marker = Marker(
                    sourceID: source.id,
                    key: Marker.key(
                        externalIdentifier: item.event.externalIdentifier,
                        occurrenceDate: item.event.occurrenceDate
                    )
                )
                blocks.append(DesiredBlock(
                    sourceID: source.id,
                    calendarId: targetCalendar.id,
                    title: renderTitle(source.titleTemplate, eventStart: item.event.start, calendar: calendar),
                    interval: item.interval,
                    isAllDay: false,
                    availability: source.availability,
                    marker: marker
                ))
            }
        }

        return blocks
    }

    /// Source events that carry no usable identity and were therefore skipped by
    /// `desiredBlocks`. Callers surface the count so the drop is never silent.
    public static func unidentifiable(_ events: [StoredEvent]) -> [StoredEvent] {
        events.filter(\.externalIdentifier.isEmpty)
    }

    /// Reconciliation diff (SPEC §6): desired + existing managed → plan.
    ///
    /// `existingOnTargets` is EVERYTHING fetched from the target calendars in the
    /// window; only events carrying a valid v1 marker enter the managed set, so a
    /// delete of an unmarked event is structurally unrepresentable.
    public static func reconcile(
        desired: [DesiredBlock],
        existingOnTargets: [StoredEvent]
    ) -> SyncPlan {
        var plan = SyncPlan()

        // Structural safety invariant: restrict to valid v1 markers before diffing.
        let managed: [(event: StoredEvent, marker: Marker)] = existingOnTargets.compactMap { event in
            guard let marker = Marker.extract(url: event.url, notes: event.notes) else { return nil }
            guard marker.isCurrentVersion else { return nil } // unknown versions: never touched
            return (event, marker)
        }

        var desiredByMarker: [Marker: DesiredBlock] = [:]
        for block in desired {
            desiredByMarker[block.marker] = block
        }

        var matchedMarkers = Set<Marker>()
        for (event, marker) in managed {
            if let block = desiredByMarker[marker] {
                matchedMarkers.insert(marker)
                let availabilityDiffers: Bool = if let mapped = availability(event.availability) {
                    mapped != block.availability
                } else {
                    false // backend can't express availability
                }
                let differs = event.start != block.interval.start
                    || event.end != block.interval.end
                    || event.title != block.title
                    || event.isAllDay != block.isAllDay
                    || event.calendarId != block.calendarId
                    || availabilityDiffers
                if differs {
                    plan.changes.append(.update(eventIdentifier: event.eventIdentifier, block))
                } else {
                    plan.unchangedCount += 1
                }
            } else {
                plan.changes.append(.delete(
                    eventIdentifier: event.eventIdentifier, marker: marker, title: event.title
                ))
            }
        }

        for block in desired where !matchedMarkers.contains(block.marker) {
            plan.changes.append(.create(block))
        }

        return plan
    }

    /// Maps a stored availability back to the config enum for comparison.
    /// notSupported compares equal to anything (backend can't express it — never
    /// generate an update solely for availability the backend won't store).
    private static func availability(_ stored: EventAvailability) -> Availability? {
        switch stored {
        case .busy: .busy
        case .free: .free
        case .tentative: .tentative
        case .unavailable: .busy
        case .notSupported: nil
        }
    }

    /// Renders a title template. Placeholders (privacy-safe only): {date}, {weekday}.
    public static func renderTitle(_ template: String, eventStart: Date, calendar: Calendar = .current) -> String {
        var result = template
        if result.contains("{date}") {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            result = result.replacingOccurrences(of: "{date}", with: formatter.string(from: eventStart))
        }
        if result.contains("{weekday}") {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "EEEE"
            result = result.replacingOccurrences(of: "{weekday}", with: formatter.string(from: eventStart))
        }
        return result
    }
}
