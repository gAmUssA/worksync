import XCTest
@testable import WorkSyncCore

final class MultiSourceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let mainTarget = CalendarRef(id: "t1", title: "Calendar", accountTitle: "Work", allowsModifications: true)
    private let travelTarget = CalendarRef(
        id: "t2", title: "Travel Blocks", accountTitle: "Work", allowsModifications: true
    )

    private var window: Interval {
        SyncPlanner.window(now: now, windowDays: 21)
    }

    private func source(_ id: String, _ mutate: (inout SourceConfig) -> Void = { _ in }) -> SourceConfig {
        var s = SourceConfig(id: id, account: "acct", calendar: "cal")
        s.minDurationMinutes = 0
        s.titleTemplate = id
        mutate(&s)
        return s
    }

    private func event(
        ext: String,
        occurrence: TimeInterval? = nil,
        offset: TimeInterval,
        minutes: Double = 60,
        availability: EventAvailability = .busy,
        allDay: Bool = false
    ) -> StoredEvent {
        let start = now.addingTimeInterval(offset)
        return StoredEvent(
            eventIdentifier: "e-\(ext)-\(offset)", externalIdentifier: ext,
            occurrenceDate: occurrence.map { Date(timeIntervalSince1970: $0) } ?? start,
            calendarId: "src", title: "Private", start: start,
            end: start.addingTimeInterval(minutes * 60),
            isAllDay: allDay, availability: availability, isDeclinedByUser: false
        )
    }

    // MARK: Cross-source dedup

    func testFirstListedSourceWinsASharedEvent() {
        // The same underlying event appears in both calendars.
        let shared = event(ext: "SHARED", offset: 3600)
        let result = SyncPlanner.desiredAcrossSources([
            SourcePlanInput(source: source("personal"), targetCalendar: mainTarget, events: [shared]),
            SourcePlanInput(source: source("travel"), targetCalendar: travelTarget, events: [shared]),
        ], window: window)

        XCTAssertEqual(result.blocks.count, 1)
        XCTAssertEqual(result.blocks[0].sourceID, "personal", "earlier-listed source wins")
        XCTAssertEqual(result.blocks[0].calendarId, mainTarget.id, "and its target calendar is used")
        XCTAssertEqual(result.duplicatesDropped["travel"], 1)
    }

    func testReorderingSourcesChangesTheWinner() {
        // Order is semantically load-bearing (SPEC §4.1) — this is why the
        // config writer must preserve it exactly.
        let shared = event(ext: "SHARED", offset: 3600)
        let result = SyncPlanner.desiredAcrossSources([
            SourcePlanInput(source: source("travel"), targetCalendar: travelTarget, events: [shared]),
            SourcePlanInput(source: source("personal"), targetCalendar: mainTarget, events: [shared]),
        ], window: window)

        XCTAssertEqual(result.blocks.count, 1)
        XCTAssertEqual(result.blocks[0].sourceID, "travel")
        XCTAssertEqual(result.blocks[0].calendarId, travelTarget.id)
    }

    func testWithinSourceRecurringSeriesAllSurvive() {
        // The regression the spec calls out by name: occurrences share one
        // external identifier, so keying on the identifier alone would drop all
        // but the first — and then delete their already-synced blockers.
        let occurrences = (0 ..< 3).map { i in
            event(ext: "SERIES", occurrence: 1_700_000_000 + Double(i) * 86400, offset: Double(i) * 86400 + 3600)
        }
        let result = SyncPlanner.desiredAcrossSources([
            SourcePlanInput(source: source("personal"), targetCalendar: mainTarget, events: occurrences),
        ], window: window)

        XCTAssertEqual(result.blocks.count, 3)
        XCTAssertEqual(result.totalDuplicatesDropped, 0)
    }

    func testSameSeriesAcrossTwoSourcesDedupesPerOccurrence() {
        let occurrences = (0 ..< 3).map { i in
            event(ext: "SERIES", occurrence: 1_700_000_000 + Double(i) * 86400, offset: Double(i) * 86400 + 3600)
        }
        let result = SyncPlanner.desiredAcrossSources([
            SourcePlanInput(source: source("personal"), targetCalendar: mainTarget, events: occurrences),
            SourcePlanInput(source: source("travel"), targetCalendar: travelTarget, events: occurrences),
        ], window: window)

        XCTAssertEqual(result.blocks.count, 3, "each occurrence survives exactly once")
        XCTAssertEqual(result.duplicatesDropped["travel"], 3)
    }

    func testFilteredOutEventDoesNotClaimItsIdentity() {
        // SPEC §5 step 5: an event a source filters out must never block a later
        // source from producing it. Here the first source has a 30-minute floor.
        let short = event(ext: "SHORT", offset: 3600, minutes: 15)
        let result = SyncPlanner.desiredAcrossSources([
            SourcePlanInput(
                source: source("strict") { $0.minDurationMinutes = 30 },
                targetCalendar: mainTarget, events: [short]
            ),
            SourcePlanInput(source: source("lenient"), targetCalendar: travelTarget, events: [short]),
        ], window: window)

        XCTAssertEqual(result.blocks.count, 1)
        XCTAssertEqual(result.blocks[0].sourceID, "lenient", "the strict source filtered it, so it never claimed it")
    }

    func testDistinctEventsAtTheSameTimeBothSurvive() {
        // Identity is never time-keyed: two different appointments in the same
        // hour are ordinary and must both produce blockers.
        let a = event(ext: "A", offset: 3600)
        let b = event(ext: "B", offset: 3600)
        let result = SyncPlanner.desiredAcrossSources([
            SourcePlanInput(source: source("personal"), targetCalendar: mainTarget, events: [a, b]),
        ], window: window)

        XCTAssertEqual(result.blocks.count, 2)
    }

    func testPerSourceTargetCalendarRouting() {
        let result = SyncPlanner.desiredAcrossSources([
            SourcePlanInput(
                source: source("personal"),
                targetCalendar: mainTarget,
                events: [event(ext: "A", offset: 3600)]
            ),
            SourcePlanInput(
                source: source("travel"),
                targetCalendar: travelTarget,
                events: [event(ext: "B", offset: 7200)]
            ),
        ], window: window)

        XCTAssertEqual(result.blocks.count, 2)
        XCTAssertEqual(result.blocks.first { $0.sourceID == "personal" }?.calendarId, mainTarget.id)
        XCTAssertEqual(result.blocks.first { $0.sourceID == "travel" }?.calendarId, travelTarget.id)
    }

    func testCoalescingNeverCrossesSourceBoundaries() {
        // Two adjacent events in different sources must stay two blocks.
        let result = SyncPlanner.desiredAcrossSources([
            SourcePlanInput(
                source: source("a") { $0.coalesce = true; $0.coalesceGapMinutes = 60 },
                targetCalendar: mainTarget, events: [event(ext: "A", offset: 0)]
            ),
            SourcePlanInput(
                source: source("b") { $0.coalesce = true; $0.coalesceGapMinutes = 60 },
                targetCalendar: mainTarget, events: [event(ext: "B", offset: 3600)]
            ),
        ], window: window)

        XCTAssertEqual(result.blocks.count, 2)
    }

    // MARK: Conflict check

    private func block(sourceID: String, offsetMinutes: Double, durationMinutes: Double) -> DesiredBlock {
        let start = now.addingTimeInterval(offsetMinutes * 60)
        return DesiredBlock(
            sourceID: sourceID, calendarId: mainTarget.id, title: "Busy",
            interval: Interval(start: start, end: start.addingTimeInterval(durationMinutes * 60)),
            isAllDay: false, availability: .busy,
            marker: Marker(sourceID: sourceID, key: String(repeating: "a", count: 16))
        )
    }

    private func workEvent(
        offsetMinutes: Double,
        durationMinutes: Double,
        calendarId: String? = nil,
        availability: EventAvailability = .busy,
        declined: Bool = false,
        marker: Marker? = nil
    ) -> StoredEvent {
        let start = now.addingTimeInterval(offsetMinutes * 60)
        return StoredEvent(
            eventIdentifier: "w-\(offsetMinutes)", externalIdentifier: "W", occurrenceDate: start,
            calendarId: calendarId ?? mainTarget.id, title: "Real meeting", start: start,
            end: start.addingTimeInterval(durationMinutes * 60),
            isAllDay: false, availability: availability, isDeclinedByUser: declined,
            url: marker?.urlString, notes: marker?.notesBlock
        )
    }

    private let skipping = { () -> SourceConfig in
        var s = SourceConfig(id: "personal", account: "a", calendar: "c")
        s.skipIfWorkBusy = true
        return s
    }()

    func testFullyCoveredBlockIsSkipped() {
        let result = SyncPlanner.applyConflictSkips(
            to: [block(sourceID: "personal", offsetMinutes: 0, durationMinutes: 60)],
            existingOnTargets: [workEvent(offsetMinutes: 0, durationMinutes: 60)],
            sources: [skipping]
        )
        XCTAssertEqual(result.skipped, 1)
        XCTAssertTrue(result.kept.isEmpty)
        XCTAssertEqual(result.skippedBySource["personal"], 1)
    }

    func testBarelyCoveredBlockIsKept() {
        // 30 of 60 minutes = 50%, under the 80% threshold.
        let result = SyncPlanner.applyConflictSkips(
            to: [block(sourceID: "personal", offsetMinutes: 0, durationMinutes: 60)],
            existingOnTargets: [workEvent(offsetMinutes: 0, durationMinutes: 30)],
            sources: [skipping]
        )
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(result.kept.count, 1)
    }

    func testDoubleBookedWorkEventsAreNotDoubleCounted() {
        // The case naive summing gets wrong: two identical 30-minute meetings
        // stacked on the same half hour cover 30 of 60 minutes (50%), not 60.
        let result = SyncPlanner.applyConflictSkips(
            to: [block(sourceID: "personal", offsetMinutes: 0, durationMinutes: 60)],
            existingOnTargets: [
                workEvent(offsetMinutes: 0, durationMinutes: 30),
                workEvent(offsetMinutes: 0, durationMinutes: 30),
            ],
            sources: [skipping]
        )
        XCTAssertEqual(result.skipped, 0, "summing durations would wrongly skip this block")
        XCTAssertEqual(result.kept.count, 1)
    }

    func testNestedWorkEventsAreNotDoubleCounted() {
        // A 60-minute meeting with a 20-minute one nested inside it.
        let result = SyncPlanner.applyConflictSkips(
            to: [block(sourceID: "personal", offsetMinutes: 0, durationMinutes: 120)],
            existingOnTargets: [
                workEvent(offsetMinutes: 0, durationMinutes: 60),
                workEvent(offsetMinutes: 20, durationMinutes: 20),
            ],
            sources: [skipping]
        )
        XCTAssertEqual(result.skipped, 0, "union is 60 of 120 = 50%")
    }

    func testAdjacentWorkEventsUnionToCrossTheThreshold() {
        // Genuine back-to-back coverage: 30 + 20 contiguous of a 60-minute
        // block is 83%, over the threshold.
        let result = SyncPlanner.applyConflictSkips(
            to: [block(sourceID: "personal", offsetMinutes: 0, durationMinutes: 60)],
            existingOnTargets: [
                workEvent(offsetMinutes: 0, durationMinutes: 30),
                workEvent(offsetMinutes: 30, durationMinutes: 20),
            ],
            sources: [skipping]
        )
        XCTAssertEqual(result.skipped, 1)
    }

    func testOurOwnBlockersNeverCountAsConflicts() {
        // Otherwise the second pass would skip every block it created on the
        // first — the whole thing would oscillate.
        let managed = workEvent(
            offsetMinutes: 0, durationMinutes: 60,
            marker: Marker(sourceID: "personal", key: String(repeating: "b", count: 16))
        )
        let result = SyncPlanner.applyConflictSkips(
            to: [block(sourceID: "personal", offsetMinutes: 0, durationMinutes: 60)],
            existingOnTargets: [managed],
            sources: [skipping]
        )
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(result.kept.count, 1)
    }

    func testFutureVersionMarkersAlsoCountAsOurs() {
        let futureMarked = StoredEvent(
            eventIdentifier: "f", externalIdentifier: "F", occurrenceDate: now,
            calendarId: mainTarget.id, title: "Busy", start: now, end: now.addingTimeInterval(3600),
            isAllDay: false, availability: .busy, isDeclinedByUser: false,
            url: "worksync://v9/personal/aaaaaaaaaaaaaaaa", notes: nil
        )
        let result = SyncPlanner.applyConflictSkips(
            to: [block(sourceID: "personal", offsetMinutes: 0, durationMinutes: 60)],
            existingOnTargets: [futureMarked],
            sources: [skipping]
        )
        XCTAssertEqual(result.skipped, 0, "a newer version's blocker is still ours, not a conflict")
    }

    func testDeclinedOrFreeWorkEventsDoNotSuppressABlock() {
        for event in [
            workEvent(offsetMinutes: 0, durationMinutes: 60, declined: true),
            workEvent(offsetMinutes: 0, durationMinutes: 60, availability: .free),
        ] {
            let result = SyncPlanner.applyConflictSkips(
                to: [block(sourceID: "personal", offsetMinutes: 0, durationMinutes: 60)],
                existingOnTargets: [event],
                sources: [skipping]
            )
            XCTAssertEqual(result.skipped, 0, "declined and free work events are not busy time")
        }
    }

    func testConflictsOnlyCountOnTheBlocksOwnTargetCalendar() {
        let elsewhere = workEvent(offsetMinutes: 0, durationMinutes: 60, calendarId: travelTarget.id)
        let result = SyncPlanner.applyConflictSkips(
            to: [block(sourceID: "personal", offsetMinutes: 0, durationMinutes: 60)],
            existingOnTargets: [elsewhere],
            sources: [skipping]
        )
        XCTAssertEqual(result.skipped, 0)
    }

    func testSourcesWithoutSkipIfWorkBusyAreNeverSkipped() {
        var never = SourceConfig(id: "flights", account: "a", calendar: "c")
        never.skipIfWorkBusy = false
        let result = SyncPlanner.applyConflictSkips(
            to: [block(sourceID: "flights", offsetMinutes: 0, durationMinutes: 60)],
            existingOnTargets: [workEvent(offsetMinutes: 0, durationMinutes: 60)],
            sources: [never]
        )
        XCTAssertEqual(result.skipped, 0, "flights always get blocked")
        XCTAssertEqual(result.kept.count, 1)
    }
}
