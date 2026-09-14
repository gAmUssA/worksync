import WorkSyncCore
import XCTest
@testable import worksync

/// Renaming a source, against the real model: what a refusal stops, what an
/// open confirmation stops, and how each is resolved.
@MainActor
final class SettingsRenameTests: XCTestCase {
    private func opened(saved: Bool = false) async throws
        -> (model: MenuBarModel, recorder: MenuBarRecorder, observer: FakeChangeObserver) {
        try await MenuBarFixture.opened(
            config: MenuBarFixture.twoSources(),
            savedSourceIDs: saved ? ["personal", "travel"] : []
        )
    }

    private func handle(_ model: MenuBarModel, _ id: String) throws -> SourceHandle {
        try XCTUnwrap(model.handle(of: id))
    }

    // MARK: A refused name stops what asked for it

    func testAddingASourceIsBlockedWhileTheNameIsInvalid() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")

        // "/" separates the fields of an event marker, so it is refused.
        model.setSourceName("team/personal", of: personal)
        model.addSource()

        XCTAssertEqual(model.editingConfig?.sources.count, 2, "no source may be added")
        XCTAssertNotNil(model.renameError)
        XCTAssertEqual(model.sourceName(of: personal), "team/personal", "the typed name survives")
    }

    func testAddingASourceProceedsOnceTheNameIsValid() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")

        MenuBarFixture.rename(model, personal, to: "home")
        model.addSource()

        XCTAssertEqual(model.editingConfig?.sources.count, 3)
        XCTAssertEqual(model.source(for: personal)?.id, "home", "the rename landed first")
        XCTAssertNil(model.renameError)
    }

    func testSelectingAnotherSourceIsBlockedWhileTheNameIsInvalid() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")
        let travel = try handle(model, "travel")

        model.setSourceName("team/personal", of: personal)
        model.seedSourceIDDraft(for: travel)

        XCTAssertEqual(model.selectedSource, personal, "the selection stays on the problem")
        XCTAssertEqual(model.sourceName(of: personal), "team/personal")
        XCTAssertNotNil(model.renameError)
    }

    func testSelectingAnotherSourceProceedsOnceTheNameIsValid() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")
        let travel = try handle(model, "travel")

        MenuBarFixture.rename(model, personal, to: "home")
        model.seedSourceIDDraft(for: travel)

        XCTAssertEqual(model.selectedSource, travel)
        XCTAssertEqual(model.source(for: personal)?.id, "home")
        XCTAssertNil(model.renameError)
    }

    func testSavingIsBlockedWhileTheNameIsInvalid() async throws {
        let (model, recorder, _) = try await opened()
        let personal = try handle(model, "personal")

        model.setSourceName("team/personal", of: personal)
        model.saveSettings()

        XCTAssertTrue(recorder.savedConfigs.isEmpty, "the writer must not be called")
        XCTAssertEqual(model.screen, .settings, "and the form stays open on the problem")
    }

    /// Clearing the field is not a way out — an empty id is refused too. The
    /// escapes are a valid name, or the original one.
    func testAnEmptyNameIsStillRefused() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")

        model.setSourceName("team/personal", of: personal)
        model.setSourceName("", of: personal)
        model.addSource()

        XCTAssertEqual(model.editingConfig?.sources.count, 2)
        XCTAssertNotNil(model.renameError)
    }

    func testRestoringTheOriginalNameUnblocksTheMove() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")
        let travel = try handle(model, "travel")

        model.setSourceName("team/personal", of: personal)
        model.seedSourceIDDraft(for: travel)
        XCTAssertEqual(model.selectedSource, personal)

        model.setSourceName("personal", of: personal)
        model.seedSourceIDDraft(for: travel)

        XCTAssertEqual(model.selectedSource, travel)
        XCTAssertEqual(model.source(for: personal)?.id, "personal")
    }

    // MARK: An open confirmation

    func testRenamingASavedSourceAsksFirst() async throws {
        let (model, _, _) = try await opened(saved: true)
        let personal = try handle(model, "personal")

        model.setSourceName("home", of: personal)
        model.commitSourceName(of: personal)

        XCTAssertNotNil(model.pendingRename, "events were written under the old id")
        XCTAssertEqual(model.source(for: personal)?.id, "personal", "nothing is renamed yet")
    }

    func testAnOpenConfirmationStopsTheAction() async throws {
        let (model, recorder, _) = try await opened(saved: true)
        let personal = try handle(model, "personal")
        let travel = try handle(model, "travel")

        model.setSourceName("home", of: personal)
        model.commitSourceName(of: personal)
        XCTAssertNotNil(model.pendingRename)

        model.seedSourceIDDraft(for: travel)
        XCTAssertEqual(model.selectedSource, personal, "the selection waits for the answer")

        model.addSource()
        XCTAssertEqual(model.editingConfig?.sources.count, 2, "and so does the add")

        model.saveSettings()
        XCTAssertTrue(recorder.savedConfigs.isEmpty, "and the save")
    }

    /// The block used to be reached only when the field was dirty, so a retained
    /// setter restoring the original name left the alert open and the guard
    /// asleep.
    func testAnOpenConfirmationStillBlocksAfterTheNameIsRestored() async throws {
        let (model, _, _) = try await opened(saved: true)
        let personal = try handle(model, "personal")
        let travel = try handle(model, "travel")

        model.setSourceName("home", of: personal)
        model.commitSourceName(of: personal)

        model.setSourceName("personal", of: personal)
        XCTAssertFalse(model.sourceNameDraft.isDirty, "the field agrees with the config again")
        XCTAssertNotNil(model.pendingRename, "but the alert is still on screen")

        model.addSource()
        XCTAssertEqual(model.editingConfig?.sources.count, 2)

        model.seedSourceIDDraft(for: travel)
        XCTAssertEqual(model.selectedSource, personal)
    }

    func testCancellingTheConfirmationLetsTheActionProceed() async throws {
        let (model, _, _) = try await opened(saved: true)
        let personal = try handle(model, "personal")
        let travel = try handle(model, "travel")

        model.setSourceName("home", of: personal)
        model.commitSourceName(of: personal)
        model.cancelPendingRename()

        XCTAssertNil(model.pendingRename)
        XCTAssertEqual(model.sourceName(of: personal), "personal", "cancelling puts the old name back")

        model.seedSourceIDDraft(for: travel)
        XCTAssertEqual(model.selectedSource, travel)
        XCTAssertEqual(model.source(for: personal)?.id, "personal")
    }

    func testConfirmingTheRenameAppliesTheCandidateThatWasPresented() async throws {
        let (model, _, _) = try await opened(saved: true)
        let personal = try handle(model, "personal")

        model.setSourceName("home", of: personal)
        model.commitSourceName(of: personal)
        let presented = try XCTUnwrap(model.pendingRename)
        XCTAssertEqual(presented.from, "personal")
        XCTAssertEqual(presented.to, "home")

        model.confirmPendingRename()

        XCTAssertNil(model.pendingRename)
        XCTAssertEqual(model.source(for: personal)?.id, "home")
        XCTAssertEqual(model.handle(of: "home"), personal)
        XCTAssertEqual(model.sourceName(of: personal), "home")

        model.addSource()
        XCTAssertEqual(model.editingConfig?.sources.count, 3, "the add proceeds once answered")
    }

    func testRenamingToAnotherSourcesNameIsRefused() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")

        model.setSourceName("travel", of: personal)
        model.commitSourceName(of: personal)

        XCTAssertNotNil(model.renameError, "two sources cannot share an id")
        XCTAssertEqual(model.source(for: personal)?.id, "personal")
    }
}
