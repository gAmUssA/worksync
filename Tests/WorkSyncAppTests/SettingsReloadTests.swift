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

    // MARK: Typing that never reached the working config

    /// A half-typed filter entry lives in `titleFilterDrafts`, not in
    /// `editingConfig`, so comparing the config against the baseline calls the
    /// form clean and the reload throws the typing away.
    func testAHalfTypedFilterEntryIsNotDiscardedByAReload() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        let personal = try XCTUnwrap(model.handle(of: "personal"))
        model.setTitleFilterDraft(.excludes, to: "half-typed", of: personal)

        var changed = try MenuBarFixture.twoSources()
        changed.sources[1].titleExcludes = ["elsewhere"]
        recorder.config = changed
        model.panelWillAppear()

        XCTAssertEqual(
            model.titleFilterDraft(.excludes, of: personal), "half-typed",
            "typing that has not been added yet is still the user's work"
        )
        XCTAssertTrue(model.configChangedOnDisk)
    }

    /// Same for the name field: the text is in `sourceNameDraft` until commit.
    func testAHalfTypedSourceNameIsNotDiscardedByAReload() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        let personal = try XCTUnwrap(model.handle(of: "personal"))
        model.setSourceName("hom", of: personal)

        var changed = try MenuBarFixture.twoSources()
        changed.sources[1].titleExcludes = ["elsewhere"]
        recorder.config = changed
        model.panelWillAppear()

        XCTAssertEqual(model.sourceName(of: personal), "hom", "mid-word, not yet committed")
        XCTAssertTrue(model.configChangedOnDisk)
    }

    func testAnUnansweredRenameWarningIsNotDiscardedByAReload() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(
            config: MenuBarFixture.twoSources(), savedSourceIDs: ["personal", "travel"]
        )
        let personal = try XCTUnwrap(model.handle(of: "personal"))
        model.setSourceName("home", of: personal)
        model.commitSourceName(of: personal)
        XCTAssertNotNil(model.pendingRename, "the warning is up")

        var changed = try MenuBarFixture.twoSources()
        changed.sources[1].titleExcludes = ["elsewhere"]
        recorder.config = changed
        model.panelWillAppear()

        XCTAssertNotNil(
            model.pendingRename,
            "a question the user is part-way through answering must survive"
        )
    }

    /// Whitespace is typing too. Trimming before the check called this clean
    /// and threw it away.
    func testAWhitespaceOnlyDraftStillCountsAsUnsavedInput() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        let personal = try XCTUnwrap(model.handle(of: "personal"))
        model.setTitleFilterDraft(.excludes, to: "  ", of: personal)

        var changed = try MenuBarFixture.twoSources()
        changed.sources[1].titleExcludes = ["elsewhere"]
        recorder.config = changed
        model.panelWillAppear()

        XCTAssertEqual(model.titleFilterDraft(.excludes, of: personal), "  ")
        XCTAssertTrue(model.configChangedOnDisk)
    }

    // MARK: State that must not outlive the config it belonged to

    func testAdoptingAReloadClearsAStaleWriterError() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        recorder.saveError = ConfigError.parseFailure("disk full")
        model.saveSettings()
        XCTAssertNotNil(model.saveError, "the failed save is what sets this up")

        recorder.saveError = nil
        var changed = try MenuBarFixture.twoSources()
        changed.sources[0].titleExcludes = ["lunch"]
        recorder.config = changed
        model.panelWillAppear()

        XCTAssertNil(
            model.saveError,
            "the error belonged to a form this reload replaced; the footer must not still show it"
        )
    }

    func testAFileRestoredToTheBaselineClearsTheWarning() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        let personal = try XCTUnwrap(model.handle(of: "personal"))
        model.updateSource(personal) { $0.titleTemplate = "Mine" }

        var changed = try MenuBarFixture.twoSources()
        changed.sources[1].titleExcludes = ["elsewhere"]
        recorder.config = changed
        model.panelWillAppear()
        XCTAssertTrue(model.configChangedOnDisk)

        // Someone undid the external edit.
        recorder.config = try MenuBarFixture.twoSources()
        model.panelWillAppear()

        XCTAssertFalse(
            model.configChangedOnDisk,
            "there is no other version left to overwrite, so the warning is a lie"
        )
    }

    func testADirtyFormStillLearnsTheFilesNewIDs() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(
            config: MenuBarFixture.twoSources(), savedSourceIDs: ["personal", "travel"]
        )
        let personal = try XCTUnwrap(model.handle(of: "personal"))
        model.updateSource(personal) { $0.titleTemplate = "Mine, unsaved" }

        var renamedOnDisk = try MenuBarFixture.twoSources()
        renamedOnDisk.sources[1].id = "trips"
        recorder.config = renamedOnDisk
        model.panelWillAppear()

        XCTAssertEqual(
            model.savedSourceIDs, ["personal", "trips"],
            "the edits stay, but the file's ids are what blockers are written under"
        )
    }

    /// The symmetric case, and the likelier one: a source added to the file by
    /// hand is not in the form's origins, so the writer rebuilds only the
    /// form's sources and drops the new block with its comments.
    func testASaveCannotSilentlyDropABlockAddedToTheFile() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        let personal = try XCTUnwrap(model.handle(of: "personal"))
        model.updateSource(personal) { $0.titleTemplate = "Mine, unsaved" }

        var withNewSource = try MenuBarFixture.twoSources()
        withNewSource.sources.append(
            SourceConfig(id: "added-by-hand", account: "iCloud", calendar: "Family")
        )
        recorder.config = withNewSource
        model.panelWillAppear()

        let problem = try XCTUnwrap(
            model.settingsProblem,
            "saving would drop the block this form never knew about"
        )
        XCTAssertTrue(problem.contains("added-by-hand"), problem)

        model.saveSettings()
        XCTAssertTrue(recorder.savedConfigs.isEmpty, "the writer must not be called")
    }

    /// A blocked FIRST open leaves the screen on the dashboard, so the reload
    /// has nothing to retry — the Settings… button is the way back, and it
    /// re-reads. Documented because the retry path above looks like it should
    /// cover this and does not.
    func testAFailedFirstOpenRecoversThroughTheSettingsButton() throws {
        let (model, recorder, _) = try MenuBarFixture.model(config: MenuBarFixture.twoSources())
        recorder.configError = ConfigError.parseFailure("unexpected ]")
        model.openSettings()
        XCTAssertEqual(model.screen, .dashboard, "a refused first open never leaves the dashboard")

        model.panelWillAppear()
        XCTAssertEqual(model.screen, .dashboard, "and the reload has no form to refresh")

        recorder.configError = nil
        model.openSettings()
        XCTAssertEqual(model.screen, .settings)
        XCTAssertNil(model.settingsBlocked)
    }

    /// `openSettings` can be called on a form that already has an alert up.
    /// The new form is a different config, so the question belongs to nothing.
    func testAFreshOpenDropsAnUnansweredRenameFromTheOldForm() async throws {
        let (model, _, _) = try await MenuBarFixture.opened(
            config: MenuBarFixture.twoSources(), savedSourceIDs: ["personal", "travel"]
        )
        let personal = try XCTUnwrap(model.handle(of: "personal"))
        model.setSourceName("home", of: personal)
        model.commitSourceName(of: personal)
        XCTAssertNotNil(model.pendingRename)

        model.openSettings()

        XCTAssertNil(
            model.pendingRename,
            "the alert would reopen against a handle this form has retired"
        )
        XCTAssertNil(model.settingsProblem, "and a clean form must not be held back by it")
    }

    /// Removing a source drops its origin on purpose. Measuring "gained"
    /// against the current origins therefore reports the user's own deletion
    /// as a block that appeared on disk, and Save never comes back.
    func testDeletingASourceDoesNotLookLikeAnExternalAddition() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        let travel = try XCTUnwrap(model.handle(of: "travel"))
        model.selectedSource = travel
        model.removeSelectedSource()

        // An unrelated hand edit elsewhere in the file.
        var edited = try MenuBarFixture.twoSources()
        edited.sources[0].titleExcludes = ["lunch"]
        recorder.config = edited
        model.panelWillAppear()

        XCTAssertNil(
            model.settingsProblem,
            "the deletion is the user's own, and is exactly what the save is for"
        )
        model.saveSettings()
        XCTAssertEqual(
            recorder.savedConfigs.last?.config.sources.map(\.id), ["personal"],
            "the deletion has to be committable"
        )
    }

    /// Drafts are stored per source, and a setter retained from a source the
    /// user has left can still deliver into its slot after the selection
    /// cleared it. Nothing renders that text, so counting it as unsaved input
    /// would refuse every future reload.
    func testAnInvisibleDraftFromAnOldSelectionDoesNotBlockAReload() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        let personal = try XCTUnwrap(model.handle(of: "personal"))
        let travel = try XCTUnwrap(model.handle(of: "travel"))

        model.setTitleFilterDraft(.excludes, to: "typed into personal", of: personal)
        model.seedSourceIDDraft(for: travel)
        // A field retained from personal delivers late, into a slot the
        // selection change already cleared.
        model.setTitleFilterDraft(.excludes, to: "late from personal", of: personal)
        XCTAssertEqual(model.titleFilterDraft(.excludes, of: travel), "", "nothing is on screen")

        var changed = try MenuBarFixture.twoSources()
        changed.sources[0].titleExcludes = ["lunch"]
        recorder.config = changed
        model.panelWillAppear()

        XCTAssertEqual(
            model.editingConfig?.sources.first?.titleExcludes, ["lunch"],
            "text nobody can see must not hold the form back forever"
        )
    }

    /// Removing a source and re-adding one with the same id leaves that id out
    /// of `sourceOrigins` on purpose — the writer must treat it as a new block,
    /// not edit the old one. The resulting config can equal the baseline, so
    /// comparing configs alone calls the form clean and the reload recreates
    /// an `id -> id` origin, quietly turning it back into an edit of the old
    /// block.
    func testARemoveAndReAddSurvivesAReload() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        let travel = try XCTUnwrap(model.handle(of: "travel"))
        model.selectedSource = travel
        model.removeSelectedSource()
        model.addSource()
        let added = try XCTUnwrap(model.selectedSource)
        model.updateSource(added) { source in
            source.id = "travel"
            source.account = "Google"
            source.calendar = "Travel"
            source.titleMatches = ["flight", "hotel"]
        }
        var changed = try MenuBarFixture.twoSources()
        changed.sources[0].titleExcludes = ["lunch"]
        recorder.config = changed
        model.panelWillAppear()

        model.saveSettings()

        let origins = try XCTUnwrap(recorder.savedConfigs.last?.origins)
        XCTAssertNil(
            origins["travel"],
            "the writer is told this is a new block; a reload must not turn it back "
                + "into an edit of the old one"
        )
    }

    /// The refused-open path abandons the form but the alert binding reads
    /// `pendingRename` directly, so it would stay attached over the blocked
    /// notice, pointing at a handle nothing answers to.
    func testARefusedOpenDropsAnOpenRenameAlert() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(
            config: MenuBarFixture.twoSources(), savedSourceIDs: ["personal", "travel"]
        )
        let personal = try XCTUnwrap(model.handle(of: "personal"))
        model.setSourceName("home", of: personal)
        model.commitSourceName(of: personal)
        XCTAssertNotNil(model.pendingRename)

        recorder.configError = ConfigError.parseFailure("unexpected ]")
        model.openSettings()

        XCTAssertNotNil(model.settingsBlocked)
        XCTAssertNil(model.pendingRename, "no alert over a form that has been abandoned")
    }

    // MARK: Recovering from a blocked form

    /// A failed `openSettings` leaves the screen blocked. Fixing the file and
    /// reopening the panel is the obvious way out, so the reload has to retry
    /// rather than sit on a baseline from the session before.
    func testFixingABrokenFileUnblocksTheFormOnTheNextShow() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        XCTAssertEqual(model.screen, .settings)

        // The user opens Settings again while the file is broken.
        recorder.configError = ConfigError.parseFailure("unexpected ]")
        model.openSettings()
        XCTAssertNotNil(model.settingsBlocked)
        XCTAssertNil(model.editingConfig)

        // They fix it and reopen the panel.
        recorder.configError = nil
        var fixed = try MenuBarFixture.twoSources()
        fixed.sources[0].titleExcludes = ["lunch"]
        recorder.config = fixed
        model.panelWillAppear()

        XCTAssertNil(model.settingsBlocked, "the blocked notice describes a file that now parses")
        XCTAssertEqual(model.editingConfig?.sources.first?.titleExcludes, ["lunch"])
    }

    func testAStillBrokenFileLeavesTheFormBlocked() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        recorder.configError = ConfigError.parseFailure("unexpected ]")
        model.openSettings()

        model.panelWillAppear()

        XCTAssertNotNil(model.settingsBlocked, "still broken, so still blocked")
        XCTAssertNil(model.editingConfig)
    }

    /// The guard has to describe the form as it is now, not as it was at the
    /// moment of the reload: removing the source that could not be matched
    /// makes the save safe again.
    func testRemovingTheUnmatchableSourceAllowsSavingAgain() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        let personal = try XCTUnwrap(model.handle(of: "personal"))
        model.updateSource(personal) { $0.titleTemplate = "Mine, unsaved" }

        // Deleted, not renamed: there is no block left for the form to lose,
        // so removing the source from the form resolves it completely. (An
        // external *rename* leaves a block the form never loaded, which stays
        // blocked — see the two drop tests above.)
        var deletedOnDisk = try MenuBarFixture.twoSources()
        deletedOnDisk.sources.removeLast()
        recorder.config = deletedOnDisk
        model.panelWillAppear()
        XCTAssertNotNil(model.settingsProblem, "travel cannot be matched on disk")

        let travel = try XCTUnwrap(model.handle(of: "travel"))
        model.selectedSource = travel
        model.removeSelectedSource()

        XCTAssertNil(
            model.settingsProblem,
            "nothing in the form points at a block that is missing any more"
        )
    }

    // MARK: What a reload must not touch

    /// `configError` also carries a failed sync, and only a completed pass
    /// clears it. Clearing it because the file happened to parse turns the
    /// menu bar icon green while the tool is still failing.
    func testAReloadDoesNotEraseASyncFailure() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        recorder.passOutcome = PassOutcome(
            disposition: .failed("calendar access was revoked"), result: nil, diagnostics: nil
        )
        model.syncNow()
        await model.passTask?.value
        XCTAssertEqual(model.configError, "calendar access was revoked")
        XCTAssertEqual(model.state, .error)

        var changed = try MenuBarFixture.twoSources()
        changed.sources[0].titleExcludes = ["lunch"]
        recorder.config = changed
        model.panelWillAppear()

        XCTAssertEqual(
            model.configError, "calendar access was revoked",
            "a file that parses says nothing about whether syncing works"
        )
        XCTAssertEqual(model.state, .error, "and the icon must not go green without a good pass")
    }

    /// The calendar list belongs to the config that was loaded with it. A hand
    /// edit can name an account the old list never had, and the pickers would
    /// then mark a perfectly valid value as missing.
    func testAdoptingAReloadAsksForTheCalendarsAgain() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        let before = recorder.calendarLookups

        var changed = try MenuBarFixture.twoSources()
        changed.sources[0].titleExcludes = ["lunch"]
        recorder.config = changed
        model.panelWillAppear()
        await model.calendarChoicesTask?.value

        XCTAssertEqual(
            recorder.calendarLookups, before + 1,
            "the list has to describe the config now on screen"
        )
    }

    // MARK: Identities the form can no longer match to the file

    /// Through the real writer, against a real file: if the form keeps edits
    /// while the file renamed a source, `sourceOrigins` still names the old id.
    /// The writer cannot find that block, so it synthesizes one and the real
    /// block — comments and all — is dropped.
    func testASaveCannotSilentlyDropABlockItCannotMatch() async throws {
        let directory = NSTemporaryDirectory() + "w3fn-origins-\(UUID().uuidString)"
        let path = directory + "/config.toml"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        func write(_ travelID: String) throws {
            try """
            [target]
            account = "Work"
            calendar = "Calendar"

            [[source]]
            id = "personal"
            account = "iCloud"
            calendar = "Personal"

            [[source]]
            # Travel block documentation, written by hand.
            id = "\(travelID)"
            account = "Google"
            calendar = "Travel"
            """.write(toFile: path, atomically: true, encoding: .utf8)
        }
        try write("travel")

        let recorder = MenuBarRecorder()
        var services = MenuBarFixture.services(recorder: recorder)
        services.loadConfig = { try ConfigLoader.load(path: path) }
        services.saveConfig = { config, origins in
            try ConfigWriter.save(config, to: path, sourceOrigins: origins)
        }
        let model = MenuBarModel(
            initialState: MenuBarInitialState(isPaused: false, lastRun: nil, savedSourceIDs: []),
            services: services
        )
        model.openSettings()
        await model.calendarChoicesTask?.value

        // An unsaved edit, so the reload keeps the form.
        let personal = try XCTUnwrap(model.handle(of: "personal"))
        model.updateSource(personal) { $0.titleTemplate = "Mine, unsaved" }

        // Meanwhile the file renames the other source.
        try write("trips")
        model.panelWillAppear()

        model.saveSettings()

        let written = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(
            written.contains("# Travel block documentation, written by hand."),
            "a save that cannot match a block must not drop it: \n\(written)"
        )
    }

    func testARestoredFileRestoresTheSavedIDsToo() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(
            config: MenuBarFixture.twoSources(), savedSourceIDs: ["personal", "travel"]
        )
        let personal = try XCTUnwrap(model.handle(of: "personal"))
        model.updateSource(personal) { $0.titleTemplate = "Mine" }

        var renamedOnDisk = try MenuBarFixture.twoSources()
        renamedOnDisk.sources[1].id = "trips"
        recorder.config = renamedOnDisk
        model.panelWillAppear()
        XCTAssertEqual(model.savedSourceIDs, ["personal", "trips"])

        // Undone: the file is what the form was opened with again.
        recorder.config = try MenuBarFixture.twoSources()
        model.panelWillAppear()

        XCTAssertEqual(
            model.savedSourceIDs, ["personal", "travel"],
            "the set describes the file as last read, so restoring the file restores it"
        )
    }

    // MARK: A failed reload must not let a stale form overwrite the file

    func testSaveIsBlockedWhileTheFileCouldNotBeReRead() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        recorder.configError = ConfigError.parseFailure("unbalanced quote on line 4")

        model.panelWillAppear()

        XCTAssertNotNil(
            model.settingsProblem,
            "Save is disabled on settingsProblem alone, so the reload failure has to be in it"
        )
    }

    func testAStaleFormDoesNotOverwriteTheFileItCouldNotRead() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        recorder.configError = ConfigError.parseFailure("unbalanced quote on line 4")
        model.panelWillAppear()

        model.saveSettings()

        XCTAssertTrue(
            recorder.savedConfigs.isEmpty,
            "writing the in-memory copy would destroy the hand-edit the user is mid-way through"
        )
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
