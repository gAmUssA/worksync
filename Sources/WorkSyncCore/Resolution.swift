import Foundation

public enum ResolutionError: Error, LocalizedError, Equatable {
    case accountNotFound(String, available: [String])
    case calendarNotFound(account: String, calendar: String, available: [String])
    case ambiguous(account: String, calendar: String, count: Int)
    case sourceIsTarget(sourceID: String, calendar: String)

    public var errorDescription: String? {
        switch self {
        case let .accountNotFound(account, available):
            "Account \"\(account)\" not found. Available accounts: \(available.joined(separator: ", ")). Run `worksync calendars` for the full list."
        case let .calendarNotFound(account, calendar, available):
            "Calendar \"\(calendar)\" not found in account \"\(account)\". Available: \(available.joined(separator: ", ")). Run `worksync calendars` for the full list."
        case let .ambiguous(account, calendar, count):
            "\(count) calendars match \"\(calendar)\" in account \"\(account)\". Rename one in Calendar.app to disambiguate."
        case let .sourceIsTarget(sourceID, calendar):
            "Source \"\(sourceID)\" resolves to target calendar \"\(calendar)\" — refusing to run (feedback loop guard)."
        }
    }
}

/// The fully resolved calendars a sync pass operates on.
public struct ResolvedCalendars: Sendable {
    /// Per source id: the calendar events are read from.
    public let sourceCalendars: [String: CalendarRef]
    /// Per source id: the calendar blockers are written to.
    public let targetCalendars: [String: CalendarRef]

    /// All distinct target calendars.
    public var allTargets: [CalendarRef] {
        var seen = Set<String>()
        return targetCalendars.values.filter { seen.insert($0.id).inserted }
    }
}

public enum Resolver {
    /// Resolves every source and target calendar, case-insensitively, and enforces
    /// the ambiguity and source==target guards (SPEC §4.1, §9).
    public static func resolve(config: Config, calendars: [CalendarRef]) throws -> ResolvedCalendars {
        var sourceCals: [String: CalendarRef] = [:]
        var targetCals: [String: CalendarRef] = [:]

        for source in config.sources {
            sourceCals[source.id] = try find(account: source.account, calendar: source.calendar, in: calendars)
            let targetTitle = source.targetCalendar.isEmpty ? config.target.calendar : source.targetCalendar
            targetCals[source.id] = try find(account: config.target.account, calendar: targetTitle, in: calendars)
        }

        for source in config.sources {
            if let src = sourceCals[source.id], let dst = targetCals[source.id], src.id == dst.id {
                throw ResolutionError.sourceIsTarget(sourceID: source.id, calendar: dst.title)
            }
            // A source must also not collide with ANY target calendar.
            if let src = sourceCals[source.id],
               targetCals.values.contains(where: { $0.id == src.id }) {
                throw ResolutionError.sourceIsTarget(sourceID: source.id, calendar: src.title)
            }
        }

        return ResolvedCalendars(sourceCalendars: sourceCals, targetCalendars: targetCals)
    }

    private static func find(account: String, calendar: String, in calendars: [CalendarRef]) throws -> CalendarRef {
        let accountMatches = calendars.filter { $0.accountTitle.caseInsensitiveCompare(account) == .orderedSame }
        guard !accountMatches.isEmpty else {
            var seen = Set<String>()
            let available = calendars.map(\.accountTitle).filter { seen.insert($0).inserted }
            throw ResolutionError.accountNotFound(account, available: available)
        }
        let matches = accountMatches.filter { $0.title.caseInsensitiveCompare(calendar) == .orderedSame }
        switch matches.count {
        case 0:
            throw ResolutionError.calendarNotFound(
                account: account, calendar: calendar,
                available: accountMatches.map(\.title)
            )
        case 1:
            return matches[0]
        default:
            throw ResolutionError.ambiguous(account: account, calendar: calendar, count: matches.count)
        }
    }
}
