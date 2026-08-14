import Foundation

public enum RunLockError: Error, LocalizedError, Equatable {
    /// The lock file itself could not be created or opened. A broken
    /// environment, not a busy one.
    case unavailable(path: String, code: Int32)

    public var errorDescription: String? {
        switch self {
        case let .unavailable(path, code):
            "Could not open the run lock at \(path): \(String(cString: strerror(code))). "
                + "Check that the directory exists and is writable."
        }
    }
}

/// Cross-process mutual exclusion for a sync pass (SPEC §9).
///
/// A manual `worksync sync` in a terminal and the menu bar app's timer must
/// never collide, so both take the same exclusive `flock` on a file next to the
/// config. If the lock is held, the caller exits 0 quietly — another pass is
/// already doing the work, and reporting that as a failure would make a normal
/// race look like an error in logs and notifications.
public final class RunLock {
    public static let defaultPath = NSString(string: "~/.config/worksync/.lock").expandingTildeInPath

    /// A SEPARATE lock, held for the menu bar app's whole lifetime so a second
    /// instance cannot start. Deliberately not the pass lock above: that one is
    /// taken and released around each sync, and a CLI `worksync sync` must
    /// still be able to run while the menu bar app is alive.
    public static let instancePath = NSString(string: "~/.config/worksync/.menubar.lock")
        .expandingTildeInPath

    private let descriptor: Int32
    private var released = false

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    /// Takes the lock.
    ///
    /// Returns nil for the one benign case — another process holds it — and
    /// throws for everything else. The distinction is the whole point: a
    /// permission or filesystem problem that made the lock file unopenable
    /// would otherwise look identical to "a pass is already running", and every
    /// sync from then on would exit 0 having done nothing. Silent, permanent,
    /// and indistinguishable from healthy in the logs.
    public static func acquire(path: String = RunLock.defaultPath) throws -> RunLock? {
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true
        )

        let descriptor = open(path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else {
            throw RunLockError.unavailable(path: path, code: errno)
        }

        // LOCK_NB: fail immediately rather than queueing behind the running
        // pass — by the time it finished, this one's window would be stale.
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            close(descriptor)
            // EWOULDBLOCK (== EAGAIN) is contention. Anything else is a real
            // failure and must not be reported as a quiet no-op.
            if failure == EWOULDBLOCK {
                return nil
            }
            throw RunLockError.unavailable(path: path, code: failure)
        }
        return RunLock(descriptor: descriptor)
    }

    /// Releases the lock. Idempotent, and safe to call from a `defer` — which
    /// is also how callers keep the lock alive for the whole pass: holding it
    /// in a variable nothing ever reads invites both a compiler warning and a
    /// reader wondering whether it can be dropped early.
    public func unlock() {
        guard !released else { return }
        released = true
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    deinit { unlock() }
}
