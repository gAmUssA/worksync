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
    case calendarNotWritable(String)
    case eventNotFound(String)
    /// A delete was attempted on an event that no longer carries a valid v1
    /// marker. Never expected in a correct pass; refusing is the point.
    case refusedUnmarkedDelete(String)

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
        case let .calendarNotWritable(title):
            "Calendar \"\(title)\" is read-only; pick a writable target calendar."
        case let .eventNotFound(id):
            "Event \(id) no longer exists (changed underneath the pass); re-run to reconcile."
        case let .refusedUnmarkedDelete(id):
            "Refused to delete event \(id): it carries no valid worksync marker. This is a bug — please report it."
        }
    }
}

/// Abstraction over the calendar backend. WorkSyncCore stays EventKit-free;
/// WorkSyncKit provides the EventKit implementation, tests use an in-memory fake.
public protocol CalendarStore {
    /// Requests full calendar access. Throws CalendarStoreError on denial.
    func requestAccess() throws

    /// Reports the permission already held. MUST NOT prompt — `doctor` calls
    /// this, and a diagnostic that raises a permission dialog is both
    /// startling and self-defeating (SPEC §16).
    func authorizationStatus() -> CalendarAccess

    /// All calendars across all accounts.
    func calendars() throws -> [CalendarRef]

    /// Concrete event occurrences in [from, to) for one calendar, recurrences expanded.
    /// Implementations MUST chunk internally if the span could exceed 4 years:
    /// EKEventStore.predicateForEvents silently truncates wider spans (SPEC §8).
    func events(in calendar: CalendarRef, from: Date, to: Date) throws -> [StoredEvent]

    // MARK: Writes

    //
    // Writes are staged and then flushed by `commit()` so a pass lands as one
    // batch (SPEC §9). Implementations MUST write the marker to BOTH locations
    // on create and update — `marker.notesBlock` into notes and
    // `marker.urlString` into url — because backends differ in which survives
    // (SPEC §7).

    /// Creates a managed blocker on the calendar named by `block.calendarId`.
    func create(_ block: DesiredBlock) throws

    /// Rewrites an existing managed event in place to match `block`, including
    /// moving it to another calendar when `block.calendarId` differs.
    func update(eventIdentifier: String, to block: DesiredBlock) throws

    /// Deletes a managed event. Implementations MUST re-verify that the event
    /// still carries a valid v1 marker and refuse otherwise: this is the last
    /// line of defense on an irreversible operation against a user's real
    /// calendar, and it costs one read (SPEC §6).
    func delete(eventIdentifier: String) throws

    /// Flushes staged writes. Called once at the end of a pass.
    func commit() throws
}
