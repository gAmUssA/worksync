import WorkSyncCore
import XCTest
@testable import worksync

/// Dismissing the panel does not close settings, so the form outlives the copy
/// of the config it was opened with. Everything here is about what the user
/// sees the next time the panel appears.
@MainActor
final class SettingsReloadTests: XCTestCase {
    /// The reported bug: edit `title_excludes` in the file, reopen the panel,
    /// and the form still shows the old list.
    func testAnExternalEditAppearsWhenThePanelIsShownAgain() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        XCTAssertEqual(model.editingConfig?.sources.first?.titleExcludes, [])

        var changed = try MenuBarFixture.twoSources()
        changed.sources[0].titleExcludes = ["lunch"]
        recorder.config = changed

        model.panelWillAppear()

        XCTAssertEqual(
            model.editingConfig?.sources.first?.titleExcludes, ["lunch"],
            "the form must show what the file now says"
        )
    }

    /// The other half of the same bug: a save from a stale form would write the
    /// in-memory copy over the external edit.
    func testReloadingReplacesWhatASaveWouldWrite() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        var changed = try MenuBarFixture.twoSources()
        changed.sources[0].titleExcludes = ["lunch"]
        recorder.config = changed

        model.panelWillAppear()
        model.saveSettings()

        XCTAssertEqual(
            recorder.savedConfigs.last?.config.sources.first?.titleExcludes, ["lunch"],
            "a save after the reload must not resurrect the config the form was opened with"
        )
    }

    func testUnsavedEditsSurviveAnExternalChange() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        let handle = try XCTUnwrap(model.handle(of: "personal"))
        model.updateSource(handle) { $0.titleTemplate = "Mine, unsaved" }

        var changed = try MenuBarFixture.twoSources()
        changed.sources[0].titleExcludes = ["lunch"]
        recorder.config = changed

        model.panelWillAppear()

        XCTAssertEqual(
            model.editingConfig?.sources.first?.titleTemplate, "Mine, unsaved",
            "typing is not discarded by a reload the user did not ask for"
        )
        XCTAssertTrue(
            model.configChangedOnDisk,
            "but the user is told the file moved underneath them"
        )
    }

    func testAnUnchangedFileLeavesTheFormAlone() async throws {
        let (model, _, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        let handle = try XCTUnwrap(model.handle(of: "travel"))
        model.selectedSource = handle
        model.setTitleFilterDraft(.excludes, to: "half-typed", of: handle)

        model.panelWillAppear()

        XCTAssertEqual(model.selectedSource, handle, "selection must not churn on every panel open")
        XCTAssertEqual(
            model.titleFilterDraft(.excludes, of: handle), "half-typed",
            "nor may a draft be cleared when nothing changed"
        )
        XCTAssertFalse(model.configChangedOnDisk)
    }

    func testTheDashboardDoesNotReadTheFileOnEveryAppearance() throws {
        let (model, recorder, _) = try MenuBarFixture.model(config: MenuBarFixture.twoSources())
        let before = recorder.configLoads

        model.panelWillAppear()

        XCTAssertEqual(
            recorder.configLoads, before,
            "settings are not open, so there is nothing to refresh"
        )
    }

    func testABrokenFileLeavesTheFormIntactAndSaysSo() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        recorder.configError = ConfigError.parseFailure("unbalanced quote on line 4")

        model.panelWillAppear()

        XCTAssertNotNil(
            model.editingConfig,
            "a broken file must not empty a form that is holding the user's work"
        )
        XCTAssertNotNil(model.configError, "and the breakage is reported, not swallowed")
    }
}
