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

/// What to do with the change observer given the current config.
///
/// A pure reconciliation rather than a one-shot "start if enabled", because
/// `change_driven` and `change_debounce_seconds` are both editable in the
/// settings screen while the app is running. Starting once and never revisiting
/// it means turning the feature off does not turn it off — the observer keeps
/// firing passes for the rest of the process lifetime, which looks exactly like
/// the app ignoring the user (SPEC §11.1: a setting that does not take effect
/// is worse than one that does not exist).
///
/// Lives here rather than in the menu bar so the lifecycle is directly
/// testable: the model holds the observer, but this decides what should happen
/// to it.
public enum ChangeObservationPlan: Equatable, Sendable {
    case start(ChangeTriggerPolicy)
    case stop
    /// Same observer, new debounce. The notification carries no payload, so a
    /// debounce change needs no re-registration — and re-registering would
    /// open a window in which changes are missed for no reason.
    case updatePolicy(ChangeTriggerPolicy)
    case doNothing

    /// - Parameter hasCompletedAPass: gates *starting* only. A successful pass
    ///   is the proof that calendar access is granted; observing before that
    ///   registers something that can never fire and reports itself as working
    ///   (SPEC §11.2). Stopping is never gated — a user turning the feature off
    ///   must be obeyed immediately, whatever else is true.
    public static func reconcile(
        config: Config,
        observing: Bool,
        currentPolicy: ChangeTriggerPolicy?,
        hasCompletedAPass: Bool
    ) -> ChangeObservationPlan {
        guard config.general.changeDriven else {
            return observing ? .stop : .doNothing
        }
        let desired = ChangeTriggerPolicy(config: config)
        guard observing else {
            return hasCompletedAPass ? .start(desired) : .doNothing
        }
        return currentPolicy == desired ? .doNothing : .updatePolicy(desired)
    }
}
