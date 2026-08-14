import XCTest
@testable import WorkSyncCore

final class PurgeScanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(url: String?, notes: String?) -> StoredEvent {
        StoredEvent(
            eventIdentifier: "e1", externalIdentifier: "x", occurrenceDate: now,
            calendarId: "cal", title: "Busy", start: now, end: now.addingTimeInterval(3600),
            isAllDay: false, availability: .busy, isDeclinedByUser: false, url: url, notes: notes
        )
    }

    func testSpanStaysWellUnderTheFourYearPredicateLimit() {
        let span = PurgeScan.span(around: now)
        let years = span.duration / (365.25 * 86400)
        XCTAssertEqual(span.start, now.addingTimeInterval(-365 * 86400))
        XCTAssertEqual(span.end, now.addingTimeInterval(365 * 86400))
        // predicateForEvents silently truncates spans wider than four years, so
        // a purge that exceeded it would report success while leaving newer
        // managed events in place (SPEC §8).
        XCTAssertLessThan(years, 4.0)
    }

    func testClaimsOwnMarkedEvents() {
        let marker = Marker(sourceID: "personal", key: "abcdefabcdefabcd")
        XCTAssertEqual(
            PurgeScan.claimable(event(url: marker.urlString, notes: nil), sourceFilter: nil),
            marker
        )
        XCTAssertEqual(
            PurgeScan.claimable(event(url: nil, notes: marker.notesBlock), sourceFilter: nil),
            marker
        )
    }

    func testIgnoresUnmarkedEvents() {
        XCTAssertNil(PurgeScan.claimable(
            event(url: "https://zoom.us/j/1", notes: "agenda"), sourceFilter: nil
        ))
    }

    func testIgnoresFutureVersionMarkers() {
        // An older binary must not delete what a newer one wrote and it cannot
        // understand.
        XCTAssertNil(PurgeScan.claimable(
            event(url: "worksync://v9/personal/abcdefabcdefabcd", notes: nil), sourceFilter: nil
        ))
    }

    func testSourceFilterSelectsOnlyThatSource() {
        let personal = Marker(sourceID: "personal", key: "1111111111111111")
        let travel = Marker(sourceID: "travel", key: "2222222222222222")
        XCTAssertNotNil(PurgeScan.claimable(event(url: personal.urlString, notes: nil), sourceFilter: "personal"))
        XCTAssertNil(PurgeScan.claimable(event(url: travel.urlString, notes: nil), sourceFilter: "personal"))
    }

    func testSourceFilterIsTheRecoveryPathForARenamedID() {
        // Renaming a source id orphans its events; --source <old-id> is the only
        // way to reach them afterwards (SPEC §4.1).
        let orphaned = Marker(sourceID: "old-name", key: "3333333333333333")
        XCTAssertNil(PurgeScan.claimable(event(url: orphaned.urlString, notes: nil), sourceFilter: "new-name"))
        XCTAssertNotNil(PurgeScan.claimable(event(url: orphaned.urlString, notes: nil), sourceFilter: "old-name"))
    }
}
