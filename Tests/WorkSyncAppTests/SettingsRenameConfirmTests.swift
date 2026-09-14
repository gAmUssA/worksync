import WorkSyncCore
import XCTest
@testable import worksync

/// The gap between raising the rename warning and answering it.
///
/// `PendingRename` holds a `SourceHandle`, so the rename can no longer land on
/// the wrong source (ADR-0005, `worksync-v8xr`). What it does not do is ask
/// again: both the question and the collision check were settled when the alert
/// opened, and the list can move underneath it while the alert is up.
@MainActor
final class SettingsRenameConfirmTests: XCTestCase {
    private func opened() async throws
        -> (model: MenuBarModel, recorder: MenuBarRecorder, observer: FakeChangeObserver) {
        try await MenuBarFixture.opened(
            config: MenuBarFixture.twoSources(), savedSourceIDs: ["personal", "travel"]
        )
    }

    private func raiseRename(
        _ model: MenuBarModel, of handle: SourceHandle, to newID: String
    ) throws {
        model.selectedSource = handle
        model.setSourceName(newID, of: handle)
        model.commitSourceName(of: handle)
        XCTAssertNotNil(model.pendingRename, "the warning has to be up for this to mean anything")
    }

    // MARK: The destination can be taken while the alert is up

    func testConfirmingIntoAnIDTakenMeanwhileIsRefused() async throws {
        let (model, _, _) = try await opened()
        let personal = try XCTUnwrap(model.handle(of: "personal"))
        try raiseRename(model, of: personal, to: "shared")

        // While the alert is up, another source takes that name.
        let travel = try XCTUnwrap(model.handle(of: "travel"))
        model.updateSource(travel) { $0.id = "shared" }

        model.confirmPendingRename()

        XCTAssertEqual(
            model.source(for: personal)?.id, "personal",
            "two sources called “shared” is a config the loader rejects"
        )
        XCTAssertNotNil(model.renameError, "and the refusal is explained where the field is")
    }

    func testConfirmingIntoATakenIDLeavesASavableForm() async throws {
        let (model, _, _) = try await opened()
        let personal = try XCTUnwrap(model.handle(of: "personal"))
        try raiseRename(model, of: personal, to: "shared")
        let travel = try XCTUnwrap(model.handle(of: "travel"))
        model.updateSource(travel) { $0.id = "shared" }

        model.confirmPendingRename()

        XCTAssertNil(model.pendingRename, "the question has been answered, one way or another")
        let ids = try XCTUnwrap(model.editingConfig?.sources.map(\.id))
        XCTAssertEqual(Set(ids).count, ids.count, "no duplicate ids reach the writer")
    }

    // MARK: The question can stop applying to the source

    // The other half of the confirm-time guard — `liveID == rename.from` — has
    // no test, and deliberately so. Every supported path that changes a
    // source's id goes through `applyRename`, which moves the handle with it,
    // and the one path that replaces ids wholesale (`adoptReloadedConfig`)
    // clears `pendingRename` first. Reaching it means writing an id straight
    // into the config while leaving `sourceHandles` behind — a state the app
    // cannot be in, and a test built on it would assert against a fiction.
    //
    // The guard stays as the cheap half of the pair: if a future path ever
    // does move an id without the handle, the question the user answered
    // stops describing the source before this notices.

    func testConfirmingASourceThatWasRemovedDoesNothing() async throws {
        let (model, _, _) = try await opened()
        let personal = try XCTUnwrap(model.handle(of: "personal"))
        try raiseRename(model, of: personal, to: "home")

        model.selectedSource = personal
        model.removeSelectedSource()

        model.confirmPendingRename()

        XCTAssertEqual(model.editingConfig?.sources.map(\.id), ["travel"])
        XCTAssertNil(model.pendingRename)
    }

    // MARK: The ordinary path still works

    func testAnUndisturbedConfirmationStillRenames() async throws {
        let (model, _, _) = try await opened()
        let personal = try XCTUnwrap(model.handle(of: "personal"))
        try raiseRename(model, of: personal, to: "home")

        model.confirmPendingRename()

        XCTAssertEqual(model.source(for: personal)?.id, "home")
        XCTAssertNil(model.renameError)
        XCTAssertNil(model.pendingRename)
    }
}
