import XCTest
@testable import WorkSyncCore

final class PlannerTests: XCTestCase {
    private let targetCal = CalendarRef(
        id: "target-1",
        title: "Calendar",
        accountTitle: "Work",
        allowsModifications: true
    )
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private var window: Interval {
        SyncPlanner.window(now: now, windowDays: 21)
    }

    private func event(
        ext: String = "EXT",
        occurrence: TimeInterval? = nil,
        startOffset: TimeInterval,
        durationMinutes: Double,
        allDay: Bool = false,
        availability: EventAvailability = .busy,
        declined: Bool = false
    ) -> StoredEvent {
        let start = now.addingTimeInterval(startOffset)
        return StoredEvent(
            eventIdentifier: "id-\(ext)-\(startOffset)",
            externalIdentifier: ext,
            occurrenceDate: occurrence.map { Date(timeIntervalSince1970: $0) } ?? start,
            calendarId: "source-1",
            title: "Private thing",
            start: start,
            end: start.addingTimeInterval(durationMinutes * 60),
            isAllDay: allDay,
            availability: availability,
            isDeclinedByUser: declined
        )
    }

    private func source(_ mutate: (inout SourceConfig) -> Void = { _ in }) -> SourceConfig {
        var s = SourceConfig(id: "personal", account: "iCloud", calendar: "Personal")
        s.minDurationMinutes = 0
        mutate(&s)
        return s
    }

    // MARK: Step-3 filters

    func testFiltersDeclinedFreeAllDayShort() {
        let events = [
            event(ext: "ok", startOffset: 3600, durationMinutes: 60),
            event(ext: "declined", startOffset: 3600, durationMinutes: 60, declined: true),
            event(ext: "free", startOffset: 3600, durationMinutes: 60, availability: .free),
            event(ext: "allday", startOffset: 3600, durationMinutes: 1440, allDay: true),
            event(ext: "short", startOffset: 3600, durationMinutes: 10),
        ]
        let src = source { $0.minDurationMinutes = 15 }
        let blocks = SyncPlanner.desiredBlocks(source: src, targetCalendar: targetCal, events: events, window: window)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(
            blocks[0].marker.key,
            Marker.key(externalIdentifier: "ok", occurrenceDate: events[0].occurrenceDate)
        )
    }

    func testAllDayIncludedWhenConfigured() {
        let events = [event(ext: "trip", startOffset: 3600, durationMinutes: 2880, allDay: true)]
        let src = source { $0.includeAllDay = true }
        let blocks = SyncPlanner.desiredBlocks(source: src, targetCalendar: targetCal, events: events, window: window)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertTrue(blocks[0].isAllDay)
    }

    // MARK: Transform

    func testPaddingApplied() {
        let events = [event(ext: "flight", startOffset: 7200, durationMinutes: 60)]
        let src = source {
            $0.paddingBeforeMinutes = 120
            $0.paddingAfterMinutes = 60
        }
        let blocks = SyncPlanner.desiredBlocks(source: src, targetCalendar: targetCal, events: events, window: window)
        XCTAssertEqual(blocks[0].interval.start, now.addingTimeInterval(7200 - 120 * 60))
        XCTAssertEqual(blocks[0].interval.end, now.addingTimeInterval(7200 + 60 * 60 + 60 * 60))
    }

    func testCoalescingWithinSource() {
        let events = [
            event(ext: "a", startOffset: 0, durationMinutes: 60),
            event(ext: "b", startOffset: 70 * 60, durationMinutes: 60), // 10-min gap
            event(ext: "c", startOffset: 300 * 60, durationMinutes: 60), // far away
        ]
        let src = source {
            $0.coalesce = true
            $0.coalesceGapMinutes = 15
        }
        let blocks = SyncPlanner.desiredBlocks(source: src, targetCalendar: targetCal, events: events, window: window)
        XCTAssertEqual(blocks.count, 2)
        let merged = blocks.first { $0.interval.duration > 65 * 60 }
        XCTAssertNotNil(merged)
        XCTAssertEqual(
            merged?.marker.key,
            Marker.coalescedKey(constituents: [
                ("a", events[0].occurrenceDate), ("b", events[1].occurrenceDate),
            ])
        )
    }

    func testWindowFiltersButNeverClamps() {
        // Event straddles the window end: must keep its REAL bounds, not clamp.
        let windowEnd = 21.0 * 86400
        let events = [event(ext: "straddle", startOffset: windowEnd - 1800, durationMinutes: 120)]
        let blocks = SyncPlanner.desiredBlocks(
            source: source(),
            targetCalendar: targetCal,
            events: events,
            window: window
        )
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(
            blocks[0].interval.end,
            now.addingTimeInterval(windowEnd - 1800 + 120 * 60),
            "interval end must extend past the window edge, never be clamped to it"
        )

        // Fully outside: dropped.
        let outside = [event(ext: "later", startOffset: windowEnd + 86400, durationMinutes: 60)]
        XCTAssertTrue(SyncPlanner.desiredBlocks(
            source: source(),
            targetCalendar: targetCal,
            events: outside,
            window: window
        ).isEmpty)
    }

    func testTitleTemplateRendering() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let start = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 UTC, a Tuesday
        let rendered = SyncPlanner.renderTitle("Busy {date} ({weekday})", eventStart: start, calendar: calendar)
        XCTAssertEqual(rendered, "Busy 2023-11-14 (Tuesday)")
    }

    // MARK: Recurring series regression (SPEC §13)

    func testRecurringOccurrencesAllSurvive() {
        // Three occurrences share one external identifier — all must produce blocks.
        let events = (0 ..< 3).map { i in
            event(
                ext: "SERIES",
                occurrence: 1_700_000_000 + Double(i) * 86400,
                startOffset: Double(i) * 86400 + 3600,
                durationMinutes: 30
            )
        }
        let blocks = SyncPlanner.desiredBlocks(
            source: source(),
            targetCalendar: targetCal,
            events: events,
            window: window
        )
        XCTAssertEqual(blocks.count, 3, "occurrences sharing an external identifier must not collapse")
        XCTAssertEqual(Set(blocks.map(\.marker.key)).count, 3, "each occurrence gets a distinct key")
    }

    // MARK: Events with no usable identity

    func testUnidentifiableEventsAreSkippedNotCollapsed() {
        // Two events at the same time with no external identifier would hash to
        // the same marker key and silently collapse into one entry in
        // reconcile()'s desired map — dropping a blocker with no trace.
        let noID = { (start: TimeInterval) in
            StoredEvent(
                eventIdentifier: "", externalIdentifier: "",
                occurrenceDate: self.now.addingTimeInterval(start),
                calendarId: "source-1", title: "Mystery",
                start: self.now.addingTimeInterval(start),
                end: self.now.addingTimeInterval(start + 3600),
                isAllDay: false, availability: .busy, isDeclinedByUser: false
            )
        }
        let events = [noID(3600), noID(3600)]
        let blocks = SyncPlanner.desiredBlocks(
            source: source(), targetCalendar: targetCal, events: events, window: window
        )
        XCTAssertTrue(blocks.isEmpty, "unidentifiable events must not produce ambiguous blocks")
        XCTAssertEqual(SyncPlanner.unidentifiable(events).count, 2, "and the drop must be reportable")
    }

    func testIdentifiableEventsAreUnaffected() {
        let events = [event(ext: "HAS-ID", startOffset: 3600, durationMinutes: 60)]
        XCTAssertTrue(SyncPlanner.unidentifiable(events).isEmpty)
        XCTAssertEqual(
            SyncPlanner.desiredBlocks(
                source: source(), targetCalendar: targetCal, events: events, window: window
            ).count,
            1
        )
    }

    // MARK: Reconciliation diff

    private func managedEvent(for block: DesiredBlock, id: String = "evt-1") -> StoredEvent {
        StoredEvent(
            eventIdentifier: id,
            externalIdentifier: "",
            occurrenceDate: block.interval.start,
            calendarId: block.calendarId,
            title: block.title,
            start: block.interval.start,
            end: block.interval.end,
            isAllDay: block.isAllDay,
            availability: .busy,
            isDeclinedByUser: false,
            url: block.marker.urlString,
            notes: block.marker.notesBlock
        )
    }

    func testReconcileCreatesWhenNoExisting() {
        let blocks = SyncPlanner.desiredBlocks(
            source: source(), targetCalendar: targetCal,
            events: [event(ext: "new", startOffset: 3600, durationMinutes: 60)], window: window
        )
        let plan = SyncPlanner.reconcile(desired: blocks, existingOnTargets: [])
        XCTAssertEqual(plan.createCount, 1)
        XCTAssertEqual(plan.summaryLine, "created=1 updated=0 deleted=0 skipped=0 unchanged=0")
    }

    func testReconcileConvergesToUnchanged() {
        // "Sync twice with no source changes performs zero writes" (SPEC §15).
        let blocks = SyncPlanner.desiredBlocks(
            source: source(), targetCalendar: targetCal,
            events: [event(ext: "steady", startOffset: 3600, durationMinutes: 60)], window: window
        )
        let existing = blocks.map { managedEvent(for: $0) }
        let plan = SyncPlanner.reconcile(desired: blocks, existingOnTargets: existing)
        XCTAssertTrue(plan.changes.isEmpty)
        XCTAssertEqual(plan.unchangedCount, 1)
    }

    func testReconcileUpdatesInPlaceOnDurationChange() {
        let events = [event(ext: "grew", startOffset: 3600, durationMinutes: 60)]
        let before = SyncPlanner.desiredBlocks(
            source: source(),
            targetCalendar: targetCal,
            events: events,
            window: window
        )
        let existing = before.map { managedEvent(for: $0) }

        // Same start (same occurrenceDate → same key), longer duration.
        let grown = [event(ext: "grew", startOffset: 3600, durationMinutes: 90)]
        var after = SyncPlanner.desiredBlocks(
            source: source(),
            targetCalendar: targetCal,
            events: grown,
            window: window
        )
        // occurrenceDate defaults to start in the helper, so keys match.
        XCTAssertEqual(after[0].marker, before[0].marker)

        let plan = SyncPlanner.reconcile(desired: after, existingOnTargets: existing)
        XCTAssertEqual(plan.updateCount, 1)
        XCTAssertEqual(plan.createCount, 0)
        XCTAssertEqual(plan.deleteCount, 0)

        after = [] // silence mutation warning
    }

    func testReconcileDeletesWhenNoLongerDesired() {
        let blocks = SyncPlanner.desiredBlocks(
            source: source(), targetCalendar: targetCal,
            events: [event(ext: "gone", startOffset: 3600, durationMinutes: 60)], window: window
        )
        let existing = blocks.map { managedEvent(for: $0) }
        let plan = SyncPlanner.reconcile(desired: [], existingOnTargets: existing)
        XCTAssertEqual(plan.deleteCount, 1)
    }

    func testReconcileNeverTouchesUnmarkedEvents() {
        // A real work meeting with no marker must be structurally untouchable.
        let realMeeting = StoredEvent(
            eventIdentifier: "real-1", externalIdentifier: "R", occurrenceDate: now,
            calendarId: targetCal.id, title: "Staff meeting",
            start: now, end: now.addingTimeInterval(3600),
            isAllDay: false, availability: .busy, isDeclinedByUser: false,
            url: "https://zoom.us/j/123", notes: "agenda"
        )
        let plan = SyncPlanner.reconcile(desired: [], existingOnTargets: [realMeeting])
        XCTAssertTrue(plan.changes.isEmpty, "unmarked events must never appear in the plan")
    }

    func testReconcileIgnoresUnknownMarkerVersions() {
        let futureMarked = StoredEvent(
            eventIdentifier: "future-1", externalIdentifier: "F", occurrenceDate: now,
            calendarId: targetCal.id, title: "Busy",
            start: now, end: now.addingTimeInterval(3600),
            isAllDay: false, availability: .busy, isDeclinedByUser: false,
            url: "worksync://v9/personal/aaaaaaaaaaaaaaaa", notes: nil
        )
        let plan = SyncPlanner.reconcile(desired: [], existingOnTargets: [futureMarked])
        XCTAssertTrue(plan.changes.isEmpty, "only v1 markers may be mutated; unknown versions are skipped")
    }

    func testDetachedOccurrenceMoveIsUpdate() {
        // A recurring occurrence detached and dragged to a new time keeps its
        // occurrenceDate → same key → in-place update, not delete+create (SPEC §6).
        let original = event(ext: "SERIES", occurrence: 1_700_000_000, startOffset: 3600, durationMinutes: 30)
        let before = SyncPlanner.desiredBlocks(
            source: source(),
            targetCalendar: targetCal,
            events: [original],
            window: window
        )
        let existing = before.map { managedEvent(for: $0) }

        let moved = event(ext: "SERIES", occurrence: 1_700_000_000, startOffset: 7200, durationMinutes: 30)
        let after = SyncPlanner.desiredBlocks(
            source: source(),
            targetCalendar: targetCal,
            events: [moved],
            window: window
        )
        XCTAssertEqual(after[0].marker, before[0].marker, "occurrenceDate keeps identity stable across the move")

        let plan = SyncPlanner.reconcile(desired: after, existingOnTargets: existing)
        XCTAssertEqual(plan.updateCount, 1)
        XCTAssertEqual(plan.deleteCount, 0)
        XCTAssertEqual(plan.createCount, 0)
    }
}
