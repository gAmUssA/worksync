import XCTest
@testable import WorkSyncCore

/// The CLI promises stable exit codes (SPEC §8); automation depends on them.
final class ExitCodesTests: XCTestCase {
    func testConfigErrorsMapToOne() {
        XCTAssertEqual(ExitCodes.code(for: ConfigError.noSources), 1)
        XCTAssertEqual(ExitCodes.code(for: ConfigError.fileNotFound("/nope.toml")), 1)
        XCTAssertEqual(ExitCodes.code(for: ConfigError.emptySourceID), 1)
    }

    func testResolutionErrorsMapToOne() {
        // Resolution failures are config problems: the account or calendar named
        // in config.toml does not exist.
        XCTAssertEqual(ExitCodes.code(for: ResolutionError.accountNotFound("X", available: [])), 1)
        XCTAssertEqual(
            ExitCodes.code(for: ResolutionError.sourceIsTarget(sourceID: "a", calendar: "Work")),
            1
        )
    }

    func testPermissionErrorsMapToTwo() {
        XCTAssertEqual(ExitCodes.code(for: CalendarStoreError.accessDenied), 2)
        XCTAssertEqual(ExitCodes.code(for: CalendarStoreError.accessRestricted), 2)
    }

    func testBackendFailureMapsToThree() {
        // Not a config error: sending the user to edit config.toml would be wrong.
        XCTAssertEqual(ExitCodes.code(for: CalendarStoreError.backendError("EventKit exploded")), 3)
    }

    func testUnknownErrorMapsToRerunnableThree() {
        struct Surprise: Error {}
        XCTAssertEqual(ExitCodes.code(for: Surprise()), 3)
    }
}
