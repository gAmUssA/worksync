import XCTest
@testable import WorkSyncCore

/// Each case here is a bug that looks fine in code review and is maddening in
/// use, which is why the policy is pure and tested rather than inline in the
/// event monitor.
final class PanelDismissPolicyTests: XCTestCase {
    func testOrdinaryOutsideClickDismisses() {
        XCTAssertFalse(PanelDismissPolicy.shouldKeepOpen(
            eventWindowClassName: "NSWindow", isPanelWindow: false, hitsStatusButton: false
        ))
    }

    func testClickInsideThePanelKeepsItOpen() {
        XCTAssertTrue(PanelDismissPolicy.shouldKeepOpen(
            eventWindowClassName: "MenuBarPanel", isPanelWindow: true, hitsStatusButton: false
        ))
    }

    func testClickOnTheStatusButtonKeepsItOpen() {
        // The button toggles. Dismissing here too would close and immediately
        // reopen the panel, so the click appears to do nothing at all.
        XCTAssertTrue(PanelDismissPolicy.shouldKeepOpen(
            eventWindowClassName: "NSStatusBarWindow", isPanelWindow: false, hitsStatusButton: true
        ))
    }

    func testMenuAndPopoverWindowsDoNotDismiss() {
        // NSMenu and hover popovers are separate windows. Treating them as
        // outside clicks tears the panel down before a button's mouse-up
        // fires, so the button never triggers.
        for className in ["NSMenuWindow", "_NSPopoverWindow", "NSCarbonMenuWindow"] {
            XCTAssertTrue(
                PanelDismissPolicy.shouldKeepOpen(
                    eventWindowClassName: className, isPanelWindow: false, hitsStatusButton: false
                ),
                "\(className) must not dismiss the panel"
            )
        }
    }

    func testUnknownWindowWithNoNameDismisses() {
        XCTAssertFalse(PanelDismissPolicy.shouldKeepOpen(
            eventWindowClassName: nil, isPanelWindow: false, hitsStatusButton: false
        ))
    }

    // MARK: Status-button hit zone

    private let button = (minX: 100.0, maxX: 130.0, minY: 1000.0)
    private let screenMaxY = 1010.0

    func testPointInsideTheButtonHits() {
        XCTAssertTrue(PanelDismissPolicy.pointHitsStatusButton(
            point: (x: 115, y: 1005), buttonRect: button, screenMaxY: screenMaxY
        ))
    }

    func testPointAtTheVeryTopOfTheScreenStillHits() {
        // A cursor slammed against the menu bar reports exactly the screen's
        // maxY, above the button's own rect. A strict rect test misses it and
        // the panel dismisses then instantly retoggles.
        XCTAssertTrue(PanelDismissPolicy.pointHitsStatusButton(
            point: (x: 115, y: screenMaxY), buttonRect: button, screenMaxY: screenMaxY
        ))
    }

    func testBoundsAreInclusive() {
        for x in [button.minX, button.maxX] {
            XCTAssertTrue(PanelDismissPolicy.pointHitsStatusButton(
                point: (x: x, y: 1005), buttonRect: button, screenMaxY: screenMaxY
            ))
        }
        XCTAssertTrue(PanelDismissPolicy.pointHitsStatusButton(
            point: (x: 115, y: button.minY), buttonRect: button, screenMaxY: screenMaxY
        ))
    }

    func testPointBesideOrBelowTheButtonMisses() {
        XCTAssertFalse(PanelDismissPolicy.pointHitsStatusButton(
            point: (x: 99, y: 1005), buttonRect: button, screenMaxY: screenMaxY
        ))
        XCTAssertFalse(PanelDismissPolicy.pointHitsStatusButton(
            point: (x: 115, y: 999), buttonRect: button, screenMaxY: screenMaxY
        ))
    }
}
