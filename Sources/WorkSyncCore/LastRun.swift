import Foundation

/// What the previous pass did, for the menu bar header and `worksync status`.
///
/// This is the ONLY thing persisted outside the calendars themselves, and it is
/// display state exclusively: reconciliation never reads it (SPEC §3). If this
/// file is deleted, corrupted, or from a future version, the next sync must
/// behave identically — which is why every read path here degrades to nil
/// rather than throwing.
public struct LastRun: Codable, Equatable, Sendable {
    public let finishedAt: Date
    public let succeeded: Bool
    /// The same summary string shown in the log and any notification, so there
    /// is one source of truth for "what happened this pass" (SPEC §11.2).
    public let summary: String
    public let errorMessage: String?

    public init(finishedAt: Date, succeeded: Bool, summary: String, errorMessage: String? = nil) {
        self.finishedAt = finishedAt
        self.succeeded = succeeded
        self.summary = summary
        self.errorMessage = errorMessage
    }

    /// How stale this run is, given the configured interval. A pass that should
    /// have happened twice over by now is the single most useful signal that
    /// nothing is running (SPEC §11.2 operational note).
    public func isStale(intervalMinutes: Int, now: Date = Date()) -> Bool {
        now.timeIntervalSince(finishedAt) > Double(intervalMinutes) * 60 * 2
    }
}

public enum LastRunStore {
    public static let defaultPath = NSString(string: "~/.config/worksync/last-run.json")
        .expandingTildeInPath

    public static func load(path: String = defaultPath) -> LastRun? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(LastRun.self, from: data)
    }

    /// Best-effort: a pass that succeeded must not be reported as failed just
    /// because this file could not be written.
    @discardableResult
    public static func save(_ run: LastRun, path: String = defaultPath) -> Bool {
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(run) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil
    }
}
