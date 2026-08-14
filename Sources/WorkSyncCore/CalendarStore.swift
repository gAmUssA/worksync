import Foundation

/// Event availability as reported by the calendar backend.
public enum EventAvailability: Sendable, Equatable {
    case notSupported
    case busy
    case free
    case tentative
    case unavailable
}

/// A calendar reference, resolved from the backend. EventKit-free.
public struct CalendarRef: Hashable, Sendable {
    /// Backend-stable calendar identifier.
    public let id: String
    public let title: String
    /// Title of the owning account (EKSource title).
    public let accountTitle: String
    public let allowsModifications: Bool

    public init(id: String, title: String, accountTitle: String, allowsModifications: Bool) {
        self.id = id
        self.title = title
        self.accountTitle = accountTitle
        self.allowsModifications = allowsModifications
    }
}

/// A concrete event occurrence fetched from a calendar. EventKit-free.
public struct StoredEvent: Sendable, Equatable {
    /// Backend event identifier (for update/delete). May be empty for fakes.
    public let eventIdentifier: String
    /// calendarItemExternalIdentifier: shared by ALL occurrences of a recurring series.
    public let externalIdentifier: String
    /// Original occurrence date: stable even when a detached occurrence is moved.
    /// Equals the start date for non-recurring events.
    public let occurrenceDate: Date
    public let calendarId: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let availability: EventAvailability
    /// True when the current user's own attendee status is declined.
    public let isDeclinedByUser: Bool
    public let url: String?
    public let notes: String?

    public init(
        eventIdentifier: String,
        externalIdentifier: String,
        occurrenceDate: Date,
        calendarId: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        availability: EventAvailability,
        isDeclinedByUser: Bool,
        url: String? = nil,
        notes: String? = nil
    ) {
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier
        self.occurrenceDate = occurrenceDate
        self.calendarId = calendarId
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.availability = availability
        self.isDeclinedByUser = isDeclinedByUser
        self.url = url
        self.notes = notes
    }
}

public enum CalendarStoreError: Error, LocalizedError {
    case accessDenied
    case accessRestricted
    case backendError(String)

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            """
            Calendar access denied. Grant Full Access in \
            System Settings > Privacy & Security > Calendars, then re-run. \
            The first run must happen interactively (e.g. from Terminal) so macOS can show the prompt.
            """
        case .accessRestricted:
            "Calendar access is restricted by device policy."
        case let .backendError(detail):
            "Calendar store error: \(detail)"
        }
    }
}

/// Abstraction over the calendar backend. WorkSyncCore stays EventKit-free;
/// WorkSyncKit provides the EventKit implementation, tests use an in-memory fake.
public protocol CalendarStore {
    /// Requests full calendar access. Throws CalendarStoreError on denial.
    func requestAccess() throws

    /// All calendars across all accounts.
    func calendars() throws -> [CalendarRef]

    /// Concrete event occurrences in [from, to) for one calendar, recurrences expanded.
    /// Implementations MUST chunk internally if the span could exceed 4 years:
    /// EKEventStore.predicateForEvents silently truncates wider spans (SPEC §8).
    func events(in calendar: CalendarRef, from: Date, to: Date) throws -> [StoredEvent]
}
