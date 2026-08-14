import XCTest
@testable import WorkSyncCore

/// End-to-end plan+apply against the in-memory store — the integration level
/// that runs in CI, where there are no calendar accounts and no TCC grants.
final class SyncEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let sourceCal = CalendarRef(id: "src", title: "Personal", accountTitle: "iCloud", allowsModifications: true)
    private let targetCal = CalendarRef(id: "dst", title: "Work", accountTitle: "Exchange", allowsModifications: true)

    private var window: Interval {
        SyncPlanner.window(now: now, windowDays: 21)
    }

    private func source(_ mutate: (inout SourceConfig) -> Void = { _ in }) -> SourceConfig {
        var s = SourceConfig(id: "personal", account: "iCloud", calendar: "Personal")
        s.minDurationMinutes = 0
        mutate(&s)
        return s
    }

    private func sourceEvent(ext: String, offset: TimeInterval, minutes: Double = 60) -> StoredEvent {
        let start = now.addingTimeInterval(offset)
        return StoredEvent(
            eventIdentifier: "src-\(ext)", externalIdentifier: ext, occurrenceDate: start,
            calendarId: sourceCal.id, title: "Dentist", start: start,
            end: start.addingTimeInterval(minutes * 60),
            isAllDay: false, availability: .busy, isDeclinedByUser: false
        )
    }

    private func makeStore(sourceEvents: [StoredEvent]) -> InMemoryCalendarStore {
        InMemoryCalendarStore(
            calendars: [sourceCal, targetCal],
            events: [sourceCal.id: sourceEvents]
        )
    }

    /// One full pass: read source, plan, apply.
    @discardableResult
    private func runPass(_ store: InMemoryCalendarStore, source: SourceConfig? = nil) throws -> ApplyResult {
        let config = source ?? self.source()
        let events = try store.events(in: sourceCal, from: window.start, to: window.end)
        let desired = SyncPlanner.desiredBlocks(
            source: config, targetCalendar: targetCal, events: events, window: window
        )
        let existing = try store.events(in: targetCal, from: window.start, to: window.end)
        let plan = SyncPlanner.reconcile(desired: desired, existingOnTargets: existing)
        return SyncEngine.apply(plan, store: store)
    }

    // MARK: Create

    func testCreatesBlockersWithMarkersInBothLocations() throws {
        let store = makeStore(sourceEvents: [sourceEvent(ext: "A", offset: 3600)])
        let result = try runPass(store)

        XCTAssertEqual(result.created, 1)
        XCTAssertFalse(result.hasFailures)

        let written = try XCTUnwrap(store.eventsByCalendar[targetCal.id]?.first)
        XCTAssertEqual(written.title, "Busy")
        // Both locations, because backends differ in which survives (SPEC §7).
        XCTAssertNotNil(try Marker.parse(XCTUnwrap(written.url)))
        XCTAssertEqual(Marker.extract(url: nil, notes: written.notes)?.sourceID, "personal")
        XCTAssertTrue(try XCTUnwrap(written.notes).contains(Marker.notesHeaderLine))
    }

    func testSourceTitleNeverLeaksToTheWorkCalendar() throws {
        let store = makeStore(sourceEvents: [sourceEvent(ext: "A", offset: 3600)])
        try runPass(store)
        let written = try XCTUnwrap(store.eventsByCalendar[targetCal.id]?.first)
        XCTAssertFalse(written.title.contains("Dentist"), "privacy invariant: source titles never appear")
    }

    // MARK: Idempotency — the headline acceptance criterion

    func testSecondPassWithNoChangesPerformsZeroWrites() throws {
        let store = makeStore(sourceEvents: [sourceEvent(ext: "A", offset: 3600)])
        XCTAssertEqual(try runPass(store).created, 1)

        let second = try runPass(store)
        XCTAssertEqual(second.created, 0)
        XCTAssertEqual(second.updated, 0)
        XCTAssertEqual(second.deleted, 0)
        XCTAssertEqual(second.unchanged, 1)
        XCTAssertEqual(store.eventsByCalendar[targetCal.id]?.count, 1)
    }

    func testTenPassesStayConvergent() throws {
        let store = makeStore(sourceEvents: [
            sourceEvent(ext: "A", offset: 3600),
            sourceEvent(ext: "B", offset: 7200),
        ])
        try runPass(store)
        for _ in 0 ..< 9 {
            let result = try runPass(store)
            XCTAssertEqual(result.created + result.updated + result.deleted, 0)
        }
        XCTAssertEqual(store.eventsByCalendar[targetCal.id]?.count, 2)
    }

    // MARK: Update and delete

    func testDurationChangeUpdatesInPlace() throws {
        let store = makeStore(sourceEvents: [sourceEvent(ext: "A", offset: 3600, minutes: 60)])
        try runPass(store)
        let originalID = store.eventsByCalendar[targetCal.id]?.first?.eventIdentifier

        // Same start (same occurrenceDate → same key), longer.
        store.replaceEvents(in: sourceCal.id, with: [sourceEvent(ext: "A", offset: 3600, minutes: 120)])
        let result = try runPass(store)

        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(result.created, 0)
        XCTAssertEqual(result.deleted, 0)
        let written = try XCTUnwrap(store.eventsByCalendar[targetCal.id]?.first)
        XCTAssertEqual(written.eventIdentifier, originalID, "update in place, not delete+create")
        XCTAssertEqual(written.end.timeIntervalSince(written.start), 120 * 60)
    }

    func testDeletedSourceEventRemovesItsBlocker() throws {
        let store = makeStore(sourceEvents: [sourceEvent(ext: "A", offset: 3600)])
        try runPass(store)
        store.replaceEvents(in: sourceCal.id, with: [])

        let result = try runPass(store)
        XCTAssertEqual(result.deleted, 1)
        XCTAssertEqual(store.eventsByCalendar[targetCal.id]?.count, 0)
    }

    func testSourceEventMarkedFreeRemovesItsBlocker() throws {
        // SPEC §15: marking a source event "Free" must remove its blocker.
        let busy = sourceEvent(ext: "A", offset: 3600)
        let store = makeStore(sourceEvents: [busy])
        try runPass(store)
        XCTAssertEqual(store.eventsByCalendar[targetCal.id]?.count, 1)

        let free = StoredEvent(
            eventIdentifier: busy.eventIdentifier, externalIdentifier: busy.externalIdentifier,
            occurrenceDate: busy.occurrenceDate, calendarId: busy.calendarId, title: busy.title,
            start: busy.start, end: busy.end, isAllDay: false,
            availability: .free, isDeclinedByUser: false
        )
        store.replaceEvents(in: sourceCal.id, with: [free])
        XCTAssertEqual(try runPass(store).deleted, 1)
        XCTAssertEqual(store.eventsByCalendar[targetCal.id]?.count, 0)

        // …and marking it busy again restores it.
        store.replaceEvents(in: sourceCal.id, with: [busy])
        XCTAssertEqual(try runPass(store).created, 1)
    }

    // MARK: Safety

    func testNeverTouchesRealWorkEvents() throws {
        let realMeeting = StoredEvent(
            eventIdentifier: "real-1", externalIdentifier: "R", occurrenceDate: now,
            calendarId: targetCal.id, title: "Board review",
            start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200),
            isAllDay: false, availability: .busy, isDeclinedByUser: false,
            url: "https://zoom.us/j/1", notes: "agenda"
        )
        let store = makeStore(sourceEvents: [])
        store.add(event: realMeeting)

        let result = try runPass(store)
        XCTAssertEqual(result.deleted, 0)
        XCTAssertEqual(store.eventsByCalendar[targetCal.id]?.count, 1, "unmarked events are untouchable")
    }

    func testStoreRefusesToDeleteAnUnmarkedEvent() {
        // Defense in depth: even if a planning bug produced such a delete, the
        // store layer refuses it rather than destroying a real event.
        let store = makeStore(sourceEvents: [])
        store.add(event: StoredEvent(
            eventIdentifier: "real-1", externalIdentifier: "R", occurrenceDate: now,
            calendarId: targetCal.id, title: "Board review", start: now, end: now.addingTimeInterval(3600),
            isAllDay: false, availability: .busy, isDeclinedByUser: false, url: nil, notes: nil
        ))
        XCTAssertThrowsError(try store.delete(eventIdentifier: "real-1")) { error in
            guard case .refusedUnmarkedDelete = error as? CalendarStoreError else {
                return XCTFail("expected refusedUnmarkedDelete, got \(error)")
            }
        }
    }

    // MARK: Partial failure

    func testPartialFailureContinuesAndReports() throws {
        let store = makeStore(sourceEvents: [
            sourceEvent(ext: "A", offset: 3600),
            sourceEvent(ext: "B", offset: 7200),
        ])
        store.failCreates = true

        let result = try runPass(store)
        XCTAssertEqual(result.created, 0)
        XCTAssertEqual(result.failures.count, 2, "both failures reported, neither aborts the pass")
        XCTAssertTrue(result.hasFailures)
        XCTAssertTrue(result.summaryLine.contains("failed=2"))
    }

    func testPassCommitsExactlyOnce() throws {
        let store = makeStore(sourceEvents: [
            sourceEvent(ext: "A", offset: 3600),
            sourceEvent(ext: "B", offset: 7200),
        ])
        try runPass(store)
        XCTAssertEqual(store.commitCount, 1, "writes land as one batch, not one commit per event")
        XCTAssertEqual(store.pendingWrites, 0)
    }

    func testFailedWritesStillCommitTheSuccessfulOnes() throws {
        let store = makeStore(sourceEvents: [sourceEvent(ext: "A", offset: 3600)])
        try runPass(store)
        store.failDeletes = true
        store.replaceEvents(in: sourceCal.id, with: [])

        let result = try runPass(store)
        XCTAssertTrue(result.hasFailures)
        XCTAssertEqual(store.commitCount, 2, "a failed write must not skip the commit")
    }
}
