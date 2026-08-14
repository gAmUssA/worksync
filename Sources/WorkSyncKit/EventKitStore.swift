import EventKit
import Foundation
import WorkSyncCore

/// EventKit-backed CalendarStore. All EventKit types stay behind this adapter.
public final class EventKitStore: CalendarStore {
    /// predicateForEvents matches at most 4 years and silently truncates wider
    /// spans (SPEC §8). Chunk conservatively below the documented limit.
    static let maxChunk: TimeInterval = 3.5 * 365.25 * 86400

    private let store = EKEventStore()

    public init() {}

    public func requestAccess() throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return
        case .restricted:
            throw CalendarStoreError.accessRestricted
        case .denied:
            throw CalendarStoreError.accessDenied
        case .notDetermined, .writeOnly, .authorized:
            // .writeOnly cannot enumerate events (queries return a virtual
            // calendar with no results), but requestFullAccessToEvents() can
            // prompt to UPGRADE write-only to full — so fall through and ask.
            break
        @unknown default:
            break
        }

        let semaphore = DispatchSemaphore(value: 0)
        var granted = false
        var requestError: Error?
        store.requestFullAccessToEvents { ok, error in
            granted = ok
            requestError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let requestError {
            throw CalendarStoreError.backendError(String(describing: requestError))
        }
        guard granted else { throw CalendarStoreError.accessDenied }
    }

    public func calendars() throws -> [CalendarRef] {
        store.calendars(for: .event).map { cal in
            CalendarRef(
                id: cal.calendarIdentifier,
                title: cal.title,
                accountTitle: cal.source?.title ?? "(no account)",
                allowsModifications: cal.allowsContentModifications
            )
        }
    }

    public func events(in calendar: CalendarRef, from: Date, to: Date) throws -> [StoredEvent] {
        guard let ekCalendar = store.calendar(withIdentifier: calendar.id) else {
            throw CalendarStoreError.backendError("Calendar \(calendar.title) (\(calendar.id)) disappeared")
        }

        var results: [StoredEvent] = []
        var seen = Set<String>() // dedupe events straddling chunk boundaries
        var chunkStart = from
        while chunkStart < to {
            let chunkEnd = min(chunkStart.addingTimeInterval(Self.maxChunk), to)
            let predicate = store.predicateForEvents(withStart: chunkStart, end: chunkEnd, calendars: [ekCalendar])
            for event in store.events(matching: predicate) {
                let stored = Self.map(event, calendarId: calendar.id)
                let identity = "\(stored.externalIdentifier)|\(stored.occurrenceDate.timeIntervalSince1970)|\(stored.start.timeIntervalSince1970)"
                if seen.insert(identity).inserted {
                    results.append(stored)
                }
            }
            chunkStart = chunkEnd
        }
        return results
    }

    // MARK: Writes

    public func create(_ block: DesiredBlock) throws {
        guard let calendar = store.calendar(withIdentifier: block.calendarId) else {
            throw CalendarStoreError.backendError("target calendar \(block.calendarId) not found")
        }
        guard calendar.allowsContentModifications else {
            throw CalendarStoreError.calendarNotWritable(calendar.title)
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        Self.write(block, onto: event)
        do {
            // commit: false — the pass flushes once at the end (SPEC §9).
            try store.save(event, span: .thisEvent, commit: false)
        } catch {
            throw CalendarStoreError.backendError(String(describing: error))
        }
    }

    public func update(eventIdentifier: String, to block: DesiredBlock) throws {
        guard let event = store.event(withIdentifier: eventIdentifier) else {
            throw CalendarStoreError.eventNotFound(eventIdentifier)
        }
        // Managed blockers are always plain non-recurring events, so
        // event(withIdentifier:) returning "the first occurrence" of a series
        // is not a hazard here — but never point this at a source event.
        if event.calendar.calendarIdentifier != block.calendarId {
            guard let destination = store.calendar(withIdentifier: block.calendarId) else {
                throw CalendarStoreError.backendError("target calendar \(block.calendarId) not found")
            }
            guard destination.allowsContentModifications else {
                throw CalendarStoreError.calendarNotWritable(destination.title)
            }
            event.calendar = destination
        }
        Self.write(block, onto: event)
        do {
            try store.save(event, span: .thisEvent, commit: false)
        } catch {
            throw CalendarStoreError.backendError(String(describing: error))
        }
    }

    public func delete(eventIdentifier: String) throws {
        guard let event = store.event(withIdentifier: eventIdentifier) else {
            throw CalendarStoreError.eventNotFound(eventIdentifier)
        }
        // Last line of defense on an irreversible write against a real
        // calendar: re-read the marker and refuse if it is not ours. Costs one
        // already-cached lookup and makes a planning bug non-destructive.
        guard let marker = Marker.extract(url: event.url?.absoluteString, notes: event.notes),
              marker.isCurrentVersion
        else {
            throw CalendarStoreError.refusedUnmarkedDelete(eventIdentifier)
        }
        do {
            try store.remove(event, span: .thisEvent, commit: false)
        } catch {
            throw CalendarStoreError.backendError(String(describing: error))
        }
    }

    public func commit() throws {
        do {
            try store.commit()
        } catch {
            throw CalendarStoreError.backendError(String(describing: error))
        }
    }

    /// Applies a desired block onto an EKEvent, writing the marker to BOTH
    /// locations: notes (primary — Google CalDAV and Exchange drop the url
    /// field entirely) and url (supplementary, survives on iCloud). SPEC §7.
    static func write(_ block: DesiredBlock, onto event: EKEvent) {
        event.title = block.title
        event.startDate = block.interval.start
        event.endDate = block.interval.end
        event.isAllDay = block.isAllDay
        event.availability = availability(block.availability, supportedBy: event.calendar)
        event.notes = block.marker.notesBlock
        event.url = URL(string: block.marker.urlString)
    }

    /// Maps configured availability onto EventKit, falling back to the
    /// calendar's default when the backend does not support the value —
    /// setting an unsupported availability is silently dropped, which would
    /// otherwise make every pass see a difference and re-update forever.
    static func availability(_ availability: Availability, supportedBy calendar: EKCalendar?) -> EKEventAvailability {
        let desired: EKEventAvailability = switch availability {
        case .busy: .busy
        case .free: .free
        case .tentative: .tentative
        }
        guard let calendar else { return desired }
        let supported = calendar.supportedEventAvailabilities
        let mask: EKCalendarEventAvailabilityMask = switch desired {
        case .free: .free
        case .tentative: .tentative
        case .unavailable: .unavailable
        default: .busy
        }
        return supported.contains(mask) ? desired : .notSupported
    }

    static func map(_ event: EKEvent, calendarId: String) -> StoredEvent {
        let availability: EventAvailability = switch event.availability {
        case .busy: .busy
        case .free: .free
        case .tentative: .tentative
        case .unavailable: .unavailable
        case .notSupported: .notSupported
        @unknown default: .notSupported
        }

        var declined = false
        if let attendees = event.attendees {
            for attendee in attendees where attendee.isCurrentUser {
                declined = attendee.participantStatus == .declined
            }
        }

        // calendarItemExternalIdentifier and eventIdentifier are both String!
        // and can come back nil for some backends. Fall back to eventIdentifier
        // (documented stable across fetches) rather than to "", which would make
        // every unidentified event at the same time hash to one marker key. An
        // event with neither is dropped by the planner rather than risking a
        // collision (SyncPlanner.unidentifiable).
        let externalID = event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? ""

        return StoredEvent(
            eventIdentifier: event.eventIdentifier ?? "",
            externalIdentifier: externalID,
            // occurrenceDate is stable across detached-occurrence moves; for
            // non-recurring events EventKit reports the start date.
            occurrenceDate: event.occurrenceDate ?? event.startDate,
            calendarId: calendarId,
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            availability: availability,
            isDeclinedByUser: declined,
            url: event.url?.absoluteString,
            notes: event.notes
        )
    }
}
