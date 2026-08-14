import Foundation

/// Watches for "something in the calendar database changed".
///
/// Declared in the EventKit-free core so the menu bar can be driven by a fake
/// in tests, and so the rules below can be exercised without a calendar
/// (SPEC §13).
public protocol CalendarChangeObserver: AnyObject {
    /// Begins observing. `onChange` may arrive on any queue.
    func start(onChange: @escaping @Sendable () -> Void)
    func stop()
}

/// What to do about a change notification that just arrived.
///
/// Pure, because both rules here are easy to get subtly wrong and impossible
/// to observe once they are: too eager and every write triggers a second pass
/// forever; too lazy and the fast path never fires at all.
public struct ChangeTriggerPolicy: Equatable, Sendable {
    /// Collapses a burst into one pass. Calendar.app posts several
    /// notifications for what a user experienced as one edit, and a sync per
    /// notification would mean several passes contending for the same lock.
    public let debounceSeconds: Int
    /// How long after our own write to disregard notifications.
    ///
    /// Every pass that writes causes the database to change, which posts a
    /// notification, which would trigger another pass — one guaranteed no-op
    /// pass behind every real one, forever.
    public let echoWindowSeconds: TimeInterval

    public init(debounceSeconds: Int, echoWindowSeconds: TimeInterval = 5) {
        self.debounceSeconds = debounceSeconds
        self.echoWindowSeconds = echoWindowSeconds
    }

    public init(config: Config) {
        self.init(debounceSeconds: config.general.changeDebounceSeconds)
    }

    public enum Action: Equatable, Sendable {
        /// Our own commit coming back at us.
        case ignoreEcho
        /// (Re-)arm the coalescing timer for this many seconds. Re-arming
        /// rather than scheduling a second timer is what makes a burst
        /// collapse instead of queueing.
        case armTimer(TimeInterval)
    }

    public func action(now: Date, lastWriteAt: Date?) -> Action {
        if let lastWriteAt, now.timeIntervalSince(lastWriteAt) < echoWindowSeconds {
            return .ignoreEcho
        }
        return .armTimer(TimeInterval(debounceSeconds))
    }

    /// A zero debounce still goes through the timer rather than firing inline:
    /// the notification arrives on an arbitrary queue mid-change, and syncing
    /// from inside that callback reads the database while it is still settling.
    public var isValid: Bool {
        debounceSeconds >= 0
    }
}
