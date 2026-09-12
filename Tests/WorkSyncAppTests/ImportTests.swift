import XCTest
@testable import worksync

/// The gate this whole target rests on: an executable target can be imported by
/// a test target, and importing it does not run `main`.
final class ImportTests: XCTestCase {
    func testTheAppModuleIsImportable() {
        XCTAssertEqual(PanelScreen.dashboard, PanelScreen.dashboard)
        XCTAssertEqual(SyncState.idle.symbolName, "calendar")
    }
}
