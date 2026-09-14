import AppKit
import SwiftUI
import WorkSyncCore
import XCTest
@testable import worksync

/// The panel is a fixed-width popover under the menu bar; only its height
/// morphs. A screen that forgets to pin its width sizes to its content, and
/// `StatusItemController.showPanel` hands that straight to `setContentSize`.
///
/// Written after a real launch reported the setup screen at
/// `{{2345, 416}, {1063, 514}}` — 1063pt against a 320pt panel. It compiled,
/// every test passed, and the panel was three times too wide.
@MainActor
final class PanelWidthTests: XCTestCase {
    private func width(of screen: PanelScreen) async throws -> CGFloat {
        let (model, recorder, _) = try MenuBarFixture.model(config: MenuBarFixture.twoSources())
        switch screen {
        case .setup:
            recorder.health = DoctorReport(findings: [
                DoctorFinding(
                    id: "calendar-access", title: "Calendar access", severity: .error,
                    detail: ["WorkSync has no access to your calendars, so nothing can be read."],
                    remediation: "Grant access in System Settings"
                ),
            ])
            model.refreshHealth()
            await model.healthTask?.value
        case .settings:
            model.openSettings()
            await model.calendarChoicesTask?.value
        case .dashboard:
            break
        }
        XCTAssertEqual(model.screen, screen, "the model has to actually be on that screen")

        let controller = NSHostingController(rootView: PanelView(model: model))
        controller.view.layoutSubtreeIfNeeded()
        return controller.view.fittingSize.width
    }

    func testEveryScreenIsThePanelWidth() async throws {
        for screen in [PanelScreen.dashboard, .settings, .setup] {
            let measured = try await width(of: screen)
            XCTAssertEqual(
                measured, Theme.width, accuracy: 0.5,
                "\(screen) measures \(measured)pt against a \(Theme.width)pt panel"
            )
        }
    }

    /// The same failure in the other axis: `showPanel` sizes the window from
    /// `fittingSize`, so an unbounded scroll area grows the panel to its whole
    /// content instead of scrolling. Five findings with wrapped detail lines
    /// is more than a short display has.
    func testAVerboseSetupScreenScrollsRatherThanGrowing() async throws {
        let (model, recorder, _) = try MenuBarFixture.model(config: MenuBarFixture.twoSources())
        recorder.health = DoctorReport(
            findings: SetupPrerequisites.ordered.map { id in
                DoctorFinding(
                    id: id, title: "\(id) is not satisfied", severity: .error,
                    detail: Array(repeating: String(repeating: "detail ", count: 12), count: 4),
                    remediation: String(repeating: "remediation ", count: 10)
                )
            }
        )
        model.refreshHealth()
        await model.healthTask?.value
        XCTAssertEqual(model.screen, .setup)

        let controller = NSHostingController(rootView: PanelView(model: model))
        controller.view.layoutSubtreeIfNeeded()
        let height = controller.view.fittingSize.height

        XCTAssertLessThanOrEqual(
            height, 560,
            "the panel grew to \(height)pt instead of scrolling its content"
        )
    }
}
