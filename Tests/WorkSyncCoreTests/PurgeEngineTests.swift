import XCTest
@testable import WorkSyncCore

/// The sweep's failure signalling: "found nothing" must never be reported after
/// a sweep that could not look everywhere.
final class PurgeEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let calA = CalendarRef(id: "a", title: "Work", accountTitle: "iCloud", allowsModifications: true)
    private let calB = CalendarRef(id: "b", title: "Travel Blocks", accountTitle: "iCloud", allowsModifications: true)

    private func managed(_ id: String, sourceID: String, calendarId: String) -> StoredEvent {
        let marker = Marker(sourceID: sourceID, key: String(repeating: "a", count: 16))
        return StoredEvent(
            eventIdentifier: id, externalIdentifier: "ext-\(id)", occurrenceDate: now,
            calendarId: calendarId, title: "Busy", start: now, end: now.addingTimeInterval(3600),
            isAllDay: false, availability: .busy, isDeclinedByUser: false,
            url: marker.urlString, notes: marker.notesBlock
        )
    }

    private func unmanaged(_ id: String, calendarId: String) -> StoredEvent {
        StoredEvent(
            eventIdentifier: id, externalIdentifier: "ext-\(id)", occurrenceDate: now,
            calendarId: calendarId, title: "Board review", start: now, end: now.addingTimeInterval(3600),
            isAllDay: false, availability: .busy, isDeclinedByUser: false,
            url: "https://zoom.us/j/1", notes: "agenda"
        )
    }

    private func makeStore() -> InMemoryCalendarStore {
        InMemoryCalendarStore(
            calendars: [calA, calB],
            events: [
                calA.id: [
                    managed("m1", sourceID: "personal", calendarId: calA.id),
                    unmanaged("u1", calendarId: calA.id),
                ],
                calB.id: [managed("m2", sourceID: "travel", calendarId: calB.id)],
            ]
        )
    }

    func testFindsManagedEventsAcrossAllCalendars() {
        let scan = PurgeEngine.scan(store: makeStore(), now: now, sourceFilter: nil)
        XCTAssertEqual(scan.found.count, 2)
        XCTAssertTrue(scan.isComplete)
        XCTAssertEqual(scan.countsBySource, ["personal": 1, "travel": 1])
    }

    func testIgnoresUnmanagedEvents() {
        let scan = PurgeEngine.scan(store: makeStore(), now: now, sourceFilter: nil)
        XCTAssertFalse(scan.found.contains { $0.title == "Board review" })
    }

    func testSourceFilterNarrowsTheSweep() {
        let scan = PurgeEngine.scan(store: makeStore(), now: now, sourceFilter: "travel")
        XCTAssertEqual(scan.found.count, 1)
        XCTAssertEqual(scan.found.first?.marker.sourceID, "travel")
    }

    // MARK: Incomplete sweeps

    func testUnreadableCalendarIsRecordedAndDoesNotAbortTheSweep() {
        let store = makeStore()
        store.failReadsForCalendarIds = [calA.id]

        let scan = PurgeEngine.scan(store: store, now: now, sourceFilter: nil)
        XCTAssertEqual(scan.found.count, 1, "the readable calendar is still swept")
        XCTAssertFalse(scan.isComplete)
        XCTAssertEqual(scan.scanFailures.count, 1)
    }

    func testEmptyResultAfterFailedScanIsNotReportedAsComplete() {
        // The dangerous case: every calendar fails, so the sweep finds nothing.
        // "No managed events found" would be a lie, and the exit code is the
        // only thing that keeps automation honest.
        let store = makeStore()
        store.failReadsForCalendarIds = [calA.id, calB.id]

        let scan = PurgeEngine.scan(store: store, now: now, sourceFilter: nil)
        XCTAssertTrue(scan.found.isEmpty)
        XCTAssertFalse(scan.isComplete, "an empty sweep that could not look anywhere is not a clean sweep")
        XCTAssertEqual(ExitCodes.code(for: CalendarStoreError.backendError("x")), 3)
    }

    func testCalendarListingFailureIsRecorded() {
        let store = makeStore()
        store.failCalendarListing = true

        let scan = PurgeEngine.scan(store: store, now: now, sourceFilter: nil)
        XCTAssertTrue(scan.found.isEmpty)
        XCTAssertFalse(scan.isComplete)
    }

    // MARK: Deletion

    func testDeleteRemovesFoundEventsAndCommitsOnce() {
        let store = makeStore()
        let scan = PurgeEngine.scan(store: store, now: now, sourceFilter: nil)

        let result = PurgeEngine.delete(scan.found, store: store)
        XCTAssertEqual(result.deleted, 2)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(store.commitCount, 1)
        XCTAssertEqual(store.allEvents.count, 1, "the unmanaged event survives")
    }

    func testDeleteContinuesPastFailures() {
        let store = makeStore()
        let scan = PurgeEngine.scan(store: store, now: now, sourceFilter: nil)
        store.failDeletes = true

        let result = PurgeEngine.delete(scan.found, store: store)
        XCTAssertEqual(result.deleted, 0)
        XCTAssertEqual(result.failures.count, 2)
        XCTAssertEqual(store.allEvents.count, 3, "nothing was removed")
    }

    func testDeleteRefusesEventsThatLostTheirMarker() {
        // Defense in depth at the store layer: even a stale scan result cannot
        // delete something that is no longer ours.
        let store = makeStore()
        let scan = PurgeEngine.scan(store: store, now: now, sourceFilter: nil)
        store.replaceEvents(in: calA.id, with: [unmanaged("m1", calendarId: calA.id)])

        let result = PurgeEngine.delete(scan.found, store: store)
        XCTAssertEqual(result.deleted, 1, "only the still-marked event is removed")
        XCTAssertEqual(result.failures.count, 1)
    }
}
