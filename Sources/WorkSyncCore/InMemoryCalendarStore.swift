import Foundation

/// In-memory CalendarStore for tests and CI (which have no calendar accounts or
/// TCC grants). Mirrors the adapter's semantics: half-open span fetch, per-calendar.
public final class InMemoryCalendarStore: CalendarStore {
    public private(set) var calendarList: [CalendarRef]
    public private(set) var eventsByCalendar: [String: [StoredEvent]]
    public var accessGranted: Bool

    public init(
        calendars: [CalendarRef] = [],
        events: [String: [StoredEvent]] = [:],
        accessGranted: Bool = true
    ) {
        self.calendarList = calendars
        self.eventsByCalendar = events
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

    // MARK: Test helpers

    public func add(calendar: CalendarRef) {
        calendarList.append(calendar)
    }

    public func add(event: StoredEvent) {
        eventsByCalendar[event.calendarId, default: []].append(event)
    }
}
