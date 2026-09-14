import AppKit
import WorkSyncCore
import XCTest
@testable import worksync

/// The wiring between AppKit and `PanelDismissPolicy`, with real windows.
///
/// `PanelDismissPolicyTests` proves the rule; it cannot prove that the app asks
/// the rule the right question. Comparing the event's window against the wrong
/// window here would leave every policy test green while the rename alert is
/// torn down before its mouse-up — the defect this covers.
@MainActor
final class PanelSheetWiringTests: XCTestCase {
    private func makePanel() -> MenuBarPanel {
        MenuBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
    }

    private func makeSheet() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }

    func testASheetAttachedToThePanelKeepsItOpen() {
        let panel = makePanel()
        let sheet = makeSheet()
        defer { panel.endSheet(sheet) }

        panel.beginSheet(sheet, completionHandler: nil)
        assertAttached(sheet, to: panel)

        XCTAssertTrue(
            MenuBarPanel.keepsPanelOpen(eventWindow: sheet, panel: panel, hitsStatusButton: false),
            "a click on the panel's own sheet is not an outside click"
        )
    }

    func testASheetOfAnotherWindowStillDismisses() {
        let panel = makePanel()
        let other = makePanel()
        let sheet = makeSheet()
        defer { other.endSheet(sheet) }

        other.beginSheet(sheet, completionHandler: nil)
        assertAttached(sheet, to: other)

        XCTAssertFalse(
            MenuBarPanel.keepsPanelOpen(eventWindow: sheet, panel: panel, hitsStatusButton: false),
            "someone else's sheet is an ordinary outside click"
        )
    }

    func testAnUnattachedWindowDismisses() {
        let panel = makePanel()
        XCTAssertFalse(
            MenuBarPanel.keepsPanelOpen(eventWindow: makeSheet(), panel: panel, hitsStatusButton: false)
        )
    }

    func testThePanelItselfKeepsItOpen() {
        let panel = makePanel()
        XCTAssertTrue(
            MenuBarPanel.keepsPanelOpen(eventWindow: panel, panel: panel, hitsStatusButton: false)
        )
    }

    /// Both nil would make `sheetParent === panel` true by accident.
    func testNoPanelAndNoWindowDoesNotCountAsASheet() {
        XCTAssertFalse(
            MenuBarPanel.keepsPanelOpen(eventWindow: nil, panel: nil, hitsStatusButton: false)
        )
    }

    /// `beginSheet` establishes `sheetParent` before it returns, so there is
    /// nothing to wait for. Asserted rather than assumed: a sheet that never
    /// attached would make every assertion below pass vacuously.
    private func assertAttached(
        _ sheet: NSWindow, to parent: NSWindow, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(
            sheet.sheetParent === parent,
            "the sheet never attached, so this test would prove nothing", file: file, line: line
        )
    }
}
