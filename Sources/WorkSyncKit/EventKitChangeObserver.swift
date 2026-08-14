import EventKit
import Foundation
import WorkSyncCore

/// Observes `EKEventStoreChanged` on its own long-lived store.
///
/// The store is a stored property and not the per-pass one on purpose:
/// notifications are filtered on the specific `EKEventStore` instance being
/// observed and stop the moment that instance deallocates (SPEC §11.2). A
/// per-pass store would post exactly nothing, silently — the failure would
/// look identical to "the calendar never changed".
public final class EventKitChangeObserver: CalendarChangeObserver, @unchecked Sendable {
    /// Retained for the observer's whole life. Apple also advises apps keep a
    /// single event store rather than creating them per operation.
    private let store = EKEventStore()
    private var token: NSObjectProtocol?
    private let lock = NSLock()

    public init() {}

    public func start(onChange: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard token == nil else { return } // idempotent; double-start would double-fire

        // The classic API rather than the macOS 26 typed
        // `EKEventStore.EventStoreChanged` message: the deployment target is
        // macOS 14, so the untyped path has to exist regardless, and carrying
        // two observer registrations for a best-effort feature buys nothing
        // but a second way for it to be registered wrongly.
        token = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            // Filtered on our own retained store, per the note above.
            object: store,
            queue: nil
        ) { _ in
            // Deliberately ignores the notification entirely. Apple documents
            // that individual changes are not described; a userInfo dictionary
            // with undocumented keys does exist in practice, but nothing in it
            // is contractual. The only correct reading is "something changed,
            // re-query" (SPEC §11.2).
            onChange()
        }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard let token else { return }
        NotificationCenter.default.removeObserver(token)
        self.token = nil
    }

    deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
