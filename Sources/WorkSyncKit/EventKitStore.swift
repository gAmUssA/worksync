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

        return StoredEvent(
            eventIdentifier: event.eventIdentifier ?? "",
            externalIdentifier: event.calendarItemExternalIdentifier ?? "",
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
