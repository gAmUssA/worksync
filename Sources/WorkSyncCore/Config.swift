import Foundation
import TOMLKit

public enum LogLevel: String, CaseIterable, Sendable {
    case error, warn, info, debug
}

public enum NotifyMode: String, CaseIterable, Sendable {
    case off, errors, always
}

public enum Availability: String, CaseIterable, Sendable {
    case busy, free, tentative
}

public struct GeneralConfig: Equatable, Sendable {
    public var windowDays: Int = 21
    public var intervalMinutes: Int = 10
    public var timezone: String = "system"
    public var logLevel: LogLevel = .info
    public var notify: NotifyMode = .errors
    public var changeDriven: Bool = false
    public var changeDebounceSeconds: Int = 20

    public init() {}
}

public struct TargetConfig: Equatable, Sendable {
    public var account: String
    public var calendar: String

    public init(account: String, calendar: String) {
        self.account = account
        self.calendar = calendar
    }
}

public struct SourceConfig: Equatable, Sendable {
    public var id: String
    public var account: String
    public var calendar: String
    public var titleTemplate: String = "Busy"
    /// Empty string means "use [target].calendar".
    public var targetCalendar: String = ""
    public var coalesce: Bool = false
    public var coalesceGapMinutes: Int = 15
    public var minDurationMinutes: Int = 0
    public var paddingBeforeMinutes: Int = 0
    public var paddingAfterMinutes: Int = 0
    public var includeAllDay: Bool = false
    public var skipIfWorkBusy: Bool = false
    public var availability: Availability = .busy

    public init(id: String, account: String, calendar: String) {
        self.id = id
        self.account = account
        self.calendar = calendar
    }
}

public struct Config: Equatable, Sendable {
    public var general: GeneralConfig
    public var target: TargetConfig
    /// Order is semantically load-bearing: first-listed source wins cross-source dedup.
    public var sources: [SourceConfig]

    public init(general: GeneralConfig, target: TargetConfig, sources: [SourceConfig]) {
        self.general = general
        self.target = target
        self.sources = sources
    }
}

public enum ConfigError: Error, LocalizedError, Equatable {
    case fileNotFound(String)
    case parseFailure(String)
    case missingField(String)
    case invalidValue(field: String, value: String, allowed: String)
    case duplicateSourceID(String)
    case emptySourceID
    case noSources

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Config file not found at \(path)"
        case .parseFailure(let detail):
            return "Failed to parse config: \(detail)"
        case .missingField(let field):
            return "Missing required config field: \(field)"
        case .invalidValue(let field, let value, let allowed):
            return "Invalid value \"\(value)\" for \(field); allowed: \(allowed)"
        case .duplicateSourceID(let id):
            return "Duplicate source id \"\(id)\"; source ids must be unique"
        case .emptySourceID:
            return "A [[source]] block has an empty id; ids are embedded in event markers and must be non-empty"
        case .noSources:
            return "Config defines no [[source]] blocks; nothing to sync"
        }
    }
}

public enum ConfigLoader {
    public static let defaultPath = NSString(string: "~/.config/worksync/config.toml").expandingTildeInPath

    public static func load(path: String) throws -> Config {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ConfigError.fileNotFound(path)
        }
        let text = try String(contentsOfFile: path, encoding: .utf8)
        return try parse(text)
    }

    public static func parse(_ text: String) throws -> Config {
        let table: TOMLTable
        do {
            table = try TOMLTable(string: text)
        } catch {
            throw ConfigError.parseFailure(String(describing: error))
        }

        var general = GeneralConfig()
        if let g = table["general"]?.table {
            if let v = g["window_days"]?.int { general.windowDays = v }
            if let v = g["interval_minutes"]?.int { general.intervalMinutes = v }
            if let v = g["timezone"]?.string { general.timezone = v }
            if let v = g["log_level"]?.string {
                general.logLevel = try parseEnum(v, field: "general.log_level")
            }
            if let v = g["notify"]?.string {
                general.notify = try parseEnum(v, field: "general.notify")
            }
            if let v = g["change_driven"]?.bool { general.changeDriven = v }
            if let v = g["change_debounce_seconds"]?.int { general.changeDebounceSeconds = v }
        }

        guard let t = table["target"]?.table else {
            throw ConfigError.missingField("[target]")
        }
        guard let targetAccount = t["account"]?.string, !targetAccount.isEmpty else {
            throw ConfigError.missingField("target.account")
        }
        guard let targetCalendar = t["calendar"]?.string, !targetCalendar.isEmpty else {
            throw ConfigError.missingField("target.calendar")
        }
        let target = TargetConfig(account: targetAccount, calendar: targetCalendar)

        var sources: [SourceConfig] = []
        if let arr = table["source"]?.array {
            for (index, element) in arr.enumerated() {
                guard let s = element.table else {
                    throw ConfigError.parseFailure("[[source]] #\(index + 1) is not a table")
                }
                guard let id = s["id"]?.string else {
                    throw ConfigError.missingField("source[\(index + 1)].id")
                }
                guard let account = s["account"]?.string, !account.isEmpty else {
                    throw ConfigError.missingField("source \"\(id)\".account")
                }
                guard let calendar = s["calendar"]?.string, !calendar.isEmpty else {
                    throw ConfigError.missingField("source \"\(id)\".calendar")
                }
                var source = SourceConfig(id: id, account: account, calendar: calendar)
                if let v = s["title_template"]?.string { source.titleTemplate = v }
                if let v = s["target_calendar"]?.string { source.targetCalendar = v }
                if let v = s["coalesce"]?.bool { source.coalesce = v }
                if let v = s["coalesce_gap_minutes"]?.int { source.coalesceGapMinutes = v }
                if let v = s["min_duration_minutes"]?.int { source.minDurationMinutes = v }
                if let v = s["padding_before_minutes"]?.int { source.paddingBeforeMinutes = v }
                if let v = s["padding_after_minutes"]?.int { source.paddingAfterMinutes = v }
                if let v = s["include_all_day"]?.bool { source.includeAllDay = v }
                if let v = s["skip_if_work_busy"]?.bool { source.skipIfWorkBusy = v }
                if let v = s["availability"]?.string {
                    source.availability = try parseEnum(v, field: "source \"\(id)\".availability")
                }
                sources.append(source)
            }
        }

        let config = Config(general: general, target: target, sources: sources)
        try validate(config)
        return config
    }

    public static func validate(_ config: Config) throws {
        guard !config.sources.isEmpty else { throw ConfigError.noSources }

        var seen = Set<String>()
        for source in config.sources {
            let id = source.id.trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty else { throw ConfigError.emptySourceID }
            guard seen.insert(id.lowercased()).inserted else {
                throw ConfigError.duplicateSourceID(source.id)
            }
        }

        try checkNonNegative(config.general.windowDays, "general.window_days", min: 1)
        try checkNonNegative(config.general.intervalMinutes, "general.interval_minutes", min: 1)
        try checkNonNegative(config.general.changeDebounceSeconds, "general.change_debounce_seconds", min: 0)
        for source in config.sources {
            try checkNonNegative(source.coalesceGapMinutes, "source \"\(source.id)\".coalesce_gap_minutes", min: 0)
            try checkNonNegative(source.minDurationMinutes, "source \"\(source.id)\".min_duration_minutes", min: 0)
            try checkNonNegative(source.paddingBeforeMinutes, "source \"\(source.id)\".padding_before_minutes", min: 0)
            try checkNonNegative(source.paddingAfterMinutes, "source \"\(source.id)\".padding_after_minutes", min: 0)
        }
    }

    private static func checkNonNegative(_ value: Int, _ field: String, min: Int) throws {
        guard value >= min else {
            throw ConfigError.invalidValue(field: field, value: String(value), allowed: ">= \(min)")
        }
    }

    private static func parseEnum<E: RawRepresentable & CaseIterable>(
        _ raw: String, field: String
    ) throws -> E where E.RawValue == String {
        guard let value = E(rawValue: raw) else {
            let allowed = E.allCases.map(\.rawValue).joined(separator: " | ")
            throw ConfigError.invalidValue(field: field, value: raw, allowed: allowed)
        }
        return value
    }
}
