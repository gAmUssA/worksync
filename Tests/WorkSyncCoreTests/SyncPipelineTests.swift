import XCTest
@testable import WorkSyncCore

/// The whole read-and-plan pipeline in one flow, driven by a real Config rather
/// than hand-assembled inputs — this is the level where step ORDER is
/// observable, and order is what M3 is about.
final class SyncPipelineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private let personalCal = CalendarRef(id: "p", title: "Personal", accountTitle: "iCloud", allowsModifications: true)
    private let travelCal = CalendarRef(id: "v", title: "Travel", accountTitle: "Google", allowsModifications: true)
    private let workCal = CalendarRef(id: "w", title: "Calendar", accountTitle: "Work", allowsModifications: true)
    private let blocksCal = CalendarRef(
        id: "b", title: "Travel Blocks", accountTitle: "Work", allowsModifications: true
    )

    private func config(_ mutate: (inout Config) -> Void = { _ in }) -> Config {
        var personal = SourceConfig(id: "personal", account: "iCloud", calendar: "Personal")
        personal.minDurationMinutes = 0
        personal.titleTemplate = "Busy"

        var travel = SourceConfig(id: "travel", account: "Google", calendar: "Travel")
        travel.minDurationMinutes = 0
        travel.titleTemplate = "Flight"
        travel.targetCalendar = "Travel Blocks"

        var config = Config(
            general: GeneralConfig(),
            target: TargetConfig(account: "Work", calendar: "Calendar"),
            sources: [personal, travel]
        )
        mutate(&config)
        return config
    }

    private func event(ext: String, calendarId: String, offsetHours: Double, hours: Double = 1) -> StoredEvent {
        let start = now.addingTimeInterval(offsetHours * 3600)
        return StoredEvent(
            eventIdentifier: "e-\(ext)", externalIdentifier: ext, occurrenceDate: start,
            calendarId: calendarId, title: "Private", start: start,
            end: start.addingTimeInterval(hours * 3600),
            isAllDay: false, availability: .busy, isDeclinedByUser: false
        )
    }

    private func store(_ events: [String: [StoredEvent]] = [:]) -> InMemoryCalendarStore {
        InMemoryCalendarStore(calendars: [personalCal, travelCal, workCal, blocksCal], events: events)
    }

    func testRoutesEachSourceToItsOwnTargetCalendar() throws {
        let store = store([
            personalCal.id: [event(ext: "A", calendarId: personalCal.id, offsetHours: 2)],
            travelCal.id: [event(ext: "B", calendarId: travelCal.id, offsetHours: 5)],
        ])
        let pass = try SyncPipeline.plan(config: config(), store: store, now: now)

        XCTAssertEqual(pass.plan.createCount, 2)
        let creates = pass.plan.changes.compactMap { change -> DesiredBlock? in
            if case let .create(block) = change {
                return block
            }
            return nil
        }
        XCTAssertEqual(creates.first { $0.sourceID == "personal" }?.calendarId, workCal.id)
        XCTAssertEqual(creates.first { $0.sourceID == "travel" }?.calendarId, blocksCal.id)
        XCTAssertEqual(pass.diagnostics.targetBySource["travel"], "Travel Blocks")
    }

    func testDedupWinnerFollowsSourceOrderAndIsReported() throws {
        // The same occurrence in both calendars: personal is listed first.
        let shared = event(ext: "SHARED", calendarId: personalCal.id, offsetHours: 2)
        let sharedInTravel = StoredEvent(
            eventIdentifier: "t-SHARED", externalIdentifier: "SHARED", occurrenceDate: shared.occurrenceDate,
            calendarId: travelCal.id, title: "Private", start: shared.start, end: shared.end,
            isAllDay: false, availability: .busy, isDeclinedByUser: false
        )
        let store = store([personalCal.id: [shared], travelCal.id: [sharedInTravel]])

        let pass = try SyncPipeline.plan(config: config(), store: store, now: now)
        XCTAssertEqual(pass.plan.createCount, 1)
        XCTAssertEqual(pass.diagnostics.duplicatesDroppedBySource["travel"], 1)
        XCTAssertNil(pass.diagnostics.duplicatesDroppedBySource["personal"])
    }

    func testReversingSourceOrderReversesTheWinner() throws {
        let shared = event(ext: "SHARED", calendarId: personalCal.id, offsetHours: 2)
        let sharedInTravel = StoredEvent(
            eventIdentifier: "t-SHARED", externalIdentifier: "SHARED", occurrenceDate: shared.occurrenceDate,
            calendarId: travelCal.id, title: "Private", start: shared.start, end: shared.end,
            isAllDay: false, availability: .busy, isDeclinedByUser: false
        )
        let store = store([personalCal.id: [shared], travelCal.id: [sharedInTravel]])

        let reversed = config { $0.sources.reverse() }
        let pass = try SyncPipeline.plan(config: reversed, store: store, now: now)
        XCTAssertEqual(pass.diagnostics.duplicatesDroppedBySource["personal"], 1)
        if case let .create(block) = pass.plan.changes[0] {
            XCTAssertEqual(block.calendarId, blocksCal.id, "travel now wins, so its target calendar is used")
        } else {
            XCTFail("expected a create")
        }
    }

    func testConflictSkipCountReachesTheSummaryLine() throws {
        // A real work meeting fully covering the block, on the block's own
        // target calendar.
        let realMeeting = StoredEvent(
            eventIdentifier: "real", externalIdentifier: "R", occurrenceDate: now.addingTimeInterval(7200),
            calendarId: workCal.id, title: "Board review",
            start: now.addingTimeInterval(7200), end: now.addingTimeInterval(10800),
            isAllDay: false, availability: .busy, isDeclinedByUser: false,
            url: "https://zoom.us/j/1", notes: "agenda"
        )
        let store = store([
            personalCal.id: [event(ext: "A", calendarId: personalCal.id, offsetHours: 2)],
            workCal.id: [realMeeting],
        ])

        let conflicting = config { $0.sources[0].skipIfWorkBusy = true }
        let pass = try SyncPipeline.plan(config: conflicting, store: store, now: now)

        XCTAssertEqual(pass.plan.createCount, 0)
        XCTAssertEqual(pass.plan.skippedCount, 1)
        XCTAssertEqual(pass.diagnostics.conflictSkippedBySource["personal"], 1)
        XCTAssertEqual(
            pass.plan.summaryLine,
            "created=0 updated=0 deleted=0 skipped=1 unchanged=0",
            "the skip has to survive into the summary the user actually reads"
        )
    }

    func testUnidentifiableEventsAreCountedPerSource() throws {
        let noID = StoredEvent(
            eventIdentifier: "", externalIdentifier: "", occurrenceDate: now.addingTimeInterval(7200),
            calendarId: personalCal.id, title: "Mystery",
            start: now.addingTimeInterval(7200), end: now.addingTimeInterval(10800),
            isAllDay: false, availability: .busy, isDeclinedByUser: false
        )
        let store = store([personalCal.id: [noID]])
        let pass = try SyncPipeline.plan(config: config(), store: store, now: now)

        XCTAssertEqual(pass.plan.createCount, 0)
        XCTAssertEqual(pass.diagnostics.unidentifiableBySource["personal"], 1)
    }

    func testFullSummaryLineAcrossCreateUpdateDeleteAndUnchanged() throws {
        // One pass, then mutate the source three different ways, and assert the
        // second pass's summary reports each transition exactly once.
        let keep = event(ext: "KEEP", calendarId: personalCal.id, offsetHours: 2)
        let grow = event(ext: "GROW", calendarId: personalCal.id, offsetHours: 5)
        let gone = event(ext: "GONE", calendarId: personalCal.id, offsetHours: 8)
        let store = store([personalCal.id: [keep, grow, gone]])

        let first = try SyncPipeline.plan(config: config(), store: store, now: now)
        XCTAssertEqual(SyncEngine.apply(first.plan, store: store).created, 3)

        store.replaceEvents(in: personalCal.id, with: [
            keep,
            event(ext: "GROW", calendarId: personalCal.id, offsetHours: 5, hours: 3), // longer
            event(ext: "NEW", calendarId: personalCal.id, offsetHours: 11), // added
            // GONE removed
        ])

        let second = try SyncPipeline.plan(config: config(), store: store, now: now)
        XCTAssertEqual(
            second.plan.summaryLine,
            "created=1 updated=1 deleted=1 skipped=0 unchanged=1"
        )
    }

    func testResolutionFailureSurfacesAsAConfigError() {
        let broken = config { $0.sources[0].calendar = "Nope" }
        XCTAssertThrowsError(try SyncPipeline.plan(config: broken, store: store(), now: now)) { error in
            XCTAssertEqual(ExitCodes.code(for: error), 1)
        }
    }

    func testFilteredEventsNeverReachTheWorkCalendar() throws {
        // Weekday and duration filters run before dedup, so a filtered event
        // cannot claim an identity either.
        let store = store([personalCal.id: [event(ext: "LONG", calendarId: personalCal.id, offsetHours: 2, hours: 9)]])
        let capped = config { $0.sources[0].maxDurationMinutes = 240 }
        let pass = try SyncPipeline.plan(config: capped, store: store, now: now)

        XCTAssertEqual(pass.plan.createCount, 0)
        XCTAssertNil(pass.diagnostics.duplicatesDroppedBySource["personal"])
    }
}
