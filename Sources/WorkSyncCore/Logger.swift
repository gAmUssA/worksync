import Foundation

public extension LogLevel {
    /// Lower is more severe. A message is emitted when its severity is at or
    /// below the configured level's.
    var severity: Int {
        switch self {
        case .error: 0
        case .warn: 1
        case .info: 2
        case .debug: 3
        }
    }

    func allows(_ level: LogLevel) -> Bool {
        level.severity <= severity
    }
}

/// Appends to `~/Library/Logs/worksync/worksync.log` with size-based rotation
/// (SPEC §8).
///
/// Unattended runs have no terminal, so the log is the only record of what
/// happened — which is exactly why it must not be allowed to grow without
/// bound on a machine syncing every ten minutes for a year.
public final class Logger: @unchecked Sendable {
    public static let defaultDirectory = NSString(string: "~/Library/Logs/worksync").expandingTildeInPath

    /// Total files kept: the live log plus `archiveCount` rotated copies.
    public static let maxBytes = 1024 * 1024
    public static let archiveCount = 4

    private let path: String
    private let level: LogLevel
    private let echoToStandardError: Bool
    private let lock = NSLock()

    public init(
        directory: String = Logger.defaultDirectory,
        level: LogLevel = .info,
        echoToStandardError: Bool = false
    ) {
        path = (directory as NSString).appendingPathComponent("worksync.log")
        self.level = level
        self.echoToStandardError = echoToStandardError
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true
        )
    }

    public func error(_ message: String) {
        log(message, at: .error)
    }

    public func warn(_ message: String) {
        log(message, at: .warn)
    }

    public func info(_ message: String) {
        log(message, at: .info)
    }

    public func debug(_ message: String) {
        log(message, at: .debug)
    }

    public func log(_ message: String, at messageLevel: LogLevel) {
        guard level.allows(messageLevel) else { return }

        let line = "\(Self.timestamp()) [\(messageLevel.rawValue)] \(message)\n"

        // The menu bar app logs from the timer, wake notifications, and user
        // actions, so writes genuinely race.
        lock.lock()
        defer { lock.unlock() }

        rotateIfNeeded(adding: line.utf8.count)
        append(line)

        if echoToStandardError {
            FileHandle.standardError.write(Data(line.utf8))
        }
    }

    // MARK: Internals

    private func append(_ line: String) {
        let data = Data(line.utf8)
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    /// Rotates when the next write would cross the cap, so a single line can
    /// never leave a file meaningfully over the limit.
    private func rotateIfNeeded(adding bytes: Int) {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int,
              size + bytes > Self.maxBytes
        else { return }

        // Drop the oldest, then shift each archive down one slot.
        try? fileManager.removeItem(atPath: archivePath(Self.archiveCount))
        for index in stride(from: Self.archiveCount - 1, through: 1, by: -1) {
            let from = archivePath(index)
            guard fileManager.fileExists(atPath: from) else { continue }
            try? fileManager.moveItem(atPath: from, toPath: archivePath(index + 1))
        }
        try? fileManager.moveItem(atPath: path, toPath: archivePath(1))
    }

    private func archivePath(_ index: Int) -> String {
        "\(path).\(index)"
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
}
