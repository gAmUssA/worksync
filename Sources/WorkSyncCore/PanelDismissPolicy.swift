import Foundation

/// When a click outside the menu bar panel should NOT dismiss it.
///
/// Deliberately pure and AppKit-free so every case below is unit-tested: each
/// one is a bug that is invisible in code review and annoying in use (SPEC
/// §11.0).
public enum PanelDismissPolicy {
    /// - Parameter isSheetOfPanel: whether the event's window is attached to
    ///   the panel as a sheet. Structural on purpose: SwiftUI's `.alert`
    ///   arrives as an `_NSAlertPanel`, but the name is AppKit's to change and
    ///   the relationship is not.
    public static func shouldKeepOpen(
        eventWindowClassName: String?,
        isPanelWindow: Bool,
        hitsStatusButton: Bool,
        isSheetOfPanel: Bool
    ) -> Bool {
        // A click inside the panel is not an outside click.
        if isPanelWindow {
            return true
        }

        // A sheet of the panel is part of the panel as far as the user is
        // concerned. Dismissing on it orders the panel out — and the sheet
        // with it — before the button's mouse-up fires, so an alert presented
        // from the settings screen cannot be answered at all.
        if isSheetOfPanel {
            return true
        }

        // The status button toggles; letting this dismiss too would close the
        // panel and immediately reopen it, so the click appears to do nothing.
        if hitsStatusButton {
            return true
        }

        // NSMenu and hover popovers are SEPARATE windows. Treating them as
        // outside clicks tears the panel down before a button's mouse-up
        // fires, so the button never triggers.
        if let name = eventWindowClassName?.lowercased(),
           name.contains("menu") || name.contains("popover") {
            return true
        }

        return false
    }

    /// The status button's hit zone, extended up to the top of the screen.
    ///
    /// A cursor slammed against the menu bar reports exactly the screen's
    /// maxY — above the button's own rect — so a strict rect test misses it and
    /// the panel dismisses then instantly retoggles. Bounds are inclusive for
    /// the same reason.
    public static func pointHitsStatusButton(
        point: (x: Double, y: Double),
        buttonRect: (minX: Double, maxX: Double, minY: Double),
        screenMaxY: Double
    ) -> Bool {
        point.x >= buttonRect.minX
            && point.x <= buttonRect.maxX
            && point.y >= buttonRect.minY
            && point.y <= screenMaxY
    }
}
