import Foundation

/// Cross-process mutual exclusion for a sync pass (SPEC §9).
///
/// A manual `worksync sync` in a terminal and the menu bar app's timer must
/// never collide, so both take the same exclusive `flock` on a file next to the
/// config. If the lock is held, the caller exits 0 quietly — another pass is
/// already doing the work, and reporting that as a failure would make a normal
/// race look like an error in logs and notifications.
public final class RunLock {
    public static let defaultPath = NSString(string: "~/.config/worksync/.lock").expandingTildeInPath

    private let descriptor: Int32
    private var released = false

    /// Returns nil when another process holds the lock.
    public init?(path: String = RunLock.defaultPath) {
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true
        )
        descriptor = open(path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { return nil }
        // LOCK_NB: fail immediately rather than queueing behind the running
        // pass — by the time it finished, this one's window would be stale.
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
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
