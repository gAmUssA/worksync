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
        // Asserting `configError` alone would prove nothing: nothing in the UI
        // renders it. The settings screen needs its own message, or the failure
        // is silent to the person looking at the form.
        let notice = try XCTUnwrap(
            model.settingsReloadError,
            "a reload failure the user cannot see is a swallowed error"
        )
        XCTAssertTrue(
            notice.contains("unbalanced quote on line 4"),
            "the notice carries the parser's reason, not a generic apology: \(notice)"
        )
    }

    func testASuccessfulReloadClearsAnEarlierReloadError() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        recorder.configError = ConfigError.parseFailure("unbalanced quote")
        model.panelWillAppear()
        XCTAssertNotNil(model.settingsReloadError)

        recorder.configError = nil
        var fixed = try MenuBarFixture.twoSources()
        fixed.sources[0].titleExcludes = ["lunch"]
        recorder.config = fixed
        model.panelWillAppear()

        XCTAssertNil(model.settingsReloadError, "a fixed file must not keep showing the old failure")
        XCTAssertEqual(model.editingConfig?.sources.first?.titleExcludes, ["lunch"])
    }

    // MARK: The saved-id set the purge warning depends on

    /// `savedSourceIDs` means "ids the config file holds", which is what
    /// decides whether renaming one can orphan blockers. A reload changes the
    /// file's ids, so leaving the set behind skips the warning for a live
    /// source.
    func testAdoptingAReloadedConfigRefreshesTheSavedIDs() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(
            config: MenuBarFixture.twoSources(), savedSourceIDs: ["personal", "travel"]
        )

        var renamedOnDisk = try MenuBarFixture.twoSources()
        renamedOnDisk.sources[0].id = "home"
        recorder.config = renamedOnDisk
        model.panelWillAppear()

        XCTAssertEqual(
            model.savedSourceIDs, ["home", "travel"],
            "the file's ids are the saved ids once the form has adopted the file"
        )
    }

    func testRenamingASourceTheFileHoldsStillWarns() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(
            config: MenuBarFixture.twoSources(), savedSourceIDs: ["personal", "travel"]
        )

        var renamedOnDisk = try MenuBarFixture.twoSources()
        renamedOnDisk.sources[0].id = "home"
        recorder.config = renamedOnDisk
        model.panelWillAppear()

        let handle = try XCTUnwrap(model.handle(of: "home"))
        model.selectedSource = handle
        model.setSourceName("house", of: handle)
        _ = model.commitSourceIDDraft()

        XCTAssertNotNil(
            model.pendingRename,
            "the sync timer writes blockers under whatever the file says, so renaming "
                + "away from it must still warn about orphans"
        )
    }

    func testOpeningSettingsAlsoRefreshesTheSavedIDs() throws {
        // The same staleness on the pre-existing path: openSettings reads the
        // file too, and never updated the set either.
        let (model, recorder, _) = try MenuBarFixture.model(
            config: MenuBarFixture.twoSources(), savedSourceIDs: ["stale"]
        )
        var onDisk = try MenuBarFixture.twoSources()
        onDisk.sources[0].id = "home"
        recorder.config = onDisk

        model.openSettings()

        XCTAssertEqual(model.savedSourceIDs, ["home", "travel"])
    }
}
