import XCTest
@testable import WorkSyncCore

final class ResolutionTests: XCTestCase {
    private func makeConfig() -> Config {
        var personal = SourceConfig(id: "personal", account: "iCloud", calendar: "Personal")
        personal.targetCalendar = ""
        var travel = SourceConfig(id: "travel", account: "Google", calendar: "Travel")
        travel.targetCalendar = "Travel Blocks"
        return Config(
            general: GeneralConfig(),
            target: TargetConfig(account: "Work Exchange", calendar: "Calendar"),
            sources: [personal, travel]
        )
    }

    private let calendars = [
        CalendarRef(id: "c1", title: "Personal", accountTitle: "iCloud", allowsModifications: true),
        CalendarRef(id: "c2", title: "Travel", accountTitle: "Google", allowsModifications: true),
        CalendarRef(id: "c3", title: "Calendar", accountTitle: "Work Exchange", allowsModifications: true),
        CalendarRef(id: "c4", title: "Travel Blocks", accountTitle: "Work Exchange", allowsModifications: true),
    ]

    func testResolvesCaseInsensitively() throws {
        var config = makeConfig()
        config.target.account = "work exchange"
        config.sources[0].calendar = "PERSONAL"
        let resolved = try Resolver.resolve(config: config, calendars: calendars)
        XCTAssertEqual(resolved.sourceCalendars["personal"]?.id, "c1")
        XCTAssertEqual(resolved.targetCalendars["personal"]?.id, "c3")
        XCTAssertEqual(resolved.targetCalendars["travel"]?.id, "c4")
        XCTAssertEqual(Set(resolved.allTargets.map(\.id)), ["c3", "c4"])
    }

    func testAccountNotFoundListsAvailable() {
        var config = makeConfig()
        config.sources[0].account = "Nope"
        XCTAssertThrowsError(try Resolver.resolve(config: config, calendars: calendars)) { error in
            guard case let .accountNotFound(name, available) = error as? ResolutionError else {
                return XCTFail("expected accountNotFound, got \(error)")
            }
            XCTAssertEqual(name, "Nope")
            XCTAssertTrue(available.contains("iCloud"))
        }
    }

    func testCalendarNotFoundListsAvailable() {
        var config = makeConfig()
        config.sources[0].calendar = "Nope"
        XCTAssertThrowsError(try Resolver.resolve(config: config, calendars: calendars)) { error in
            guard case let .calendarNotFound(_, _, available) = error as? ResolutionError else {
                return XCTFail("expected calendarNotFound, got \(error)")
            }
            XCTAssertEqual(available, ["Personal"])
        }
    }

    func testAmbiguousDuplicateTitlesHardError() {
        let dupes = calendars + [
            CalendarRef(id: "c5", title: "Personal", accountTitle: "iCloud", allowsModifications: true),
        ]
        XCTAssertThrowsError(try Resolver.resolve(config: makeConfig(), calendars: dupes)) { error in
            guard case .ambiguous = error as? ResolutionError else {
                return XCTFail("expected ambiguous, got \(error)")
            }
        }
    }

    func testSourceEqualsTargetGuard() {
        // Source reads from the same calendar the target writes to → feedback loop.
        var config = makeConfig()
        config.sources[0].account = "Work Exchange"
        config.sources[0].calendar = "Calendar"
        XCTAssertThrowsError(try Resolver.resolve(config: config, calendars: calendars)) { error in
            guard case .sourceIsTarget = error as? ResolutionError else {
                return XCTFail("expected sourceIsTarget, got \(error)")
            }
        }
    }
}
