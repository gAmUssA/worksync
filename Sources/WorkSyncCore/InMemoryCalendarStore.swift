import Foundation

/// In-memory CalendarStore for tests and CI (which have no calendar accounts or
/// TCC grants). Mirrors the adapter's semantics: half-open span fetch,
/// per-calendar storage, staged writes flushed by commit(), and the same
/// marker-verification refusal on delete.
public final class InMemoryCalendarStore: CalendarStore {
    public private(set) var calendarList: [CalendarRef]
    public private(set) var eventsByCalendar: [String: [StoredEvent]]
    public var accessGranted: Bool

    /// Set to fail the next write of a given kind, to exercise partial-failure
    /// handling without needing a misbehaving backend.
    public var failCreates = false
    public var failDeletes = false
    public var failCommit = false

    /// Counts of staged-but-uncommitted writes, so tests can assert batching.
    public private(set) var pendingWrites = 0
    public private(set) var commitCount = 0

    private var nextID = 1

    public init(
        calendars: [CalendarRef] = [],
        events: [String: [StoredEvent]] = [:],
        accessGranted: Bool = true
    ) {
        calendarList = calendars
        eventsByCalendar = events
        self.accessGranted = accessGranted
    }

    public func requestAccess() throws {
        guard accessGranted else { throw CalendarStoreError.accessDenied }
    }

    public func calendars() throws -> [CalendarRef] {
        calendarList
    }

    public func events(in calendar: CalendarRef, from: Date, to: Date) throws -> [StoredEvent] {
        let span = Interval(start: from, end: to)
        return (eventsByCalendar[calendar.id] ?? []).filter {
            Interval(start: $0.start, end: $0.end).overlaps(span)
        }
    }

    // MARK: Writes

    public func create(_ block: DesiredBlock) throws {
        if failCreates {
            throw CalendarStoreError.backendError("injected create failure")
        }
        guard let calendar = calendarList.first(where: { $0.id == block.calendarId }) else {
            throw CalendarStoreError.backendError("unknown calendar \(block.calendarId)")
        }
        guard calendar.allowsModifications else {
            throw CalendarStoreError.calendarNotWritable(calendar.title)
        }
        let id = "mem-\(nextID)"
        nextID += 1
        eventsByCalendar[block.calendarId, default: []].append(materialize(block, eventIdentifier: id))
        pendingWrites += 1
    }

    public func update(eventIdentifier: String, to block: DesiredBlock) throws {
        guard let location = locate(eventIdentifier) else {
            throw CalendarStoreError.eventNotFound(eventIdentifier)
        }
        eventsByCalendar[location.calendarId]?.remove(at: location.index)
        // A target-calendar change is an update, so the event may land elsewhere.
        eventsByCalendar[block.calendarId, default: []]
            .append(materialize(block, eventIdentifier: eventIdentifier))
        pendingWrites += 1
    }

    public func delete(eventIdentifier: String) throws {
        if failDeletes {
            throw CalendarStoreError.backendError("injected delete failure")
        }
        guard let location = locate(eventIdentifier) else {
            throw CalendarStoreError.eventNotFound(eventIdentifier)
        }
        let event = eventsByCalendar[location.calendarId]![location.index]
        guard let marker = Marker.extract(url: event.url, notes: event.notes), marker.isCurrentVersion else {
            throw CalendarStoreError.refusedUnmarkedDelete(eventIdentifier)
        }
        eventsByCalendar[location.calendarId]?.remove(at: location.index)
        pendingWrites += 1
    }

    public func commit() throws {
        if failCommit {
            throw CalendarStoreError.backendError("injected commit failure")
        }
        commitCount += 1
        pendingWrites = 0
    }

    // MARK: Helpers

    /// Builds the stored form of a desired block, writing the marker to BOTH
    /// locations exactly as a real backend adapter must.
    private func materialize(_ block: DesiredBlock, eventIdentifier: String) -> StoredEvent {
        StoredEvent(
            eventIdentifier: eventIdentifier,
            externalIdentifier: "managed-\(eventIdentifier)",
            occurrenceDate: block.interval.start,
            calendarId: block.calendarId,
            title: block.title,
            start: block.interval.start,
            end: block.interval.end,
            isAllDay: block.isAllDay,
            availability: storedAvailability(block.availability),
            isDeclinedByUser: false,
            url: block.marker.urlString,
            notes: block.marker.notesBlock
        )
    }

    private func storedAvailability(_ availability: Availability) -> EventAvailability {
        switch availability {
        case .busy: .busy
        case .free: .free
        case .tentative: .tentative
        }
    }

    private func locate(_ eventIdentifier: String) -> (calendarId: String, index: Int)? {
        for (calendarId, events) in eventsByCalendar {
            if let index = events.firstIndex(where: { $0.eventIdentifier == eventIdentifier }) {
                return (calendarId, index)
            }
        }
        return nil
    }

    // MARK: Test helpers

    public func add(calendar: CalendarRef) {
        calendarList.append(calendar)
    }

    public func add(event: StoredEvent) {
        eventsByCalendar[event.calendarId, default: []].append(event)
    }

    /// Replaces a calendar's contents, simulating the user editing the source
    /// calendar between passes.
    public func replaceEvents(in calendarId: String, with events: [StoredEvent]) {
        eventsByCalendar[calendarId] = events
    }

    public var allEvents: [StoredEvent] {
        eventsByCalendar.values.flatMap { $0 }
    }
}
