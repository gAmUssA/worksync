import WorkSyncCore
import XCTest
@testable import worksync

/// Switching between sources, against the real `MenuBarModel`.
///
/// Every case here was previously asserted against a hand-written `Editor` in
/// `WorkSyncCoreTests` that mirrored the model's composition. A mirror passes
/// while the real thing drifts, which is the failure this target removes: these
/// call `openSettings`, `select`, `addSource`, `setSourceName` and the rest on
/// the model that ships.
@MainActor
final class SettingsSelectionTests: XCTestCase {
    private func opened(savedIDs: Set<String> = []) async throws
        -> (model: MenuBarModel, recorder: MenuBarRecorder, observer: FakeChangeObserver) {
        try await MenuBarFixture.opened(
            config: MenuBarFixture.twoSources(), savedSourceIDs: savedIDs
        )
    }

    private func handle(_ model: MenuBarModel, _ id: String) throws -> SourceHandle {
        try XCTUnwrap(model.handle(of: id), "no handle for “\(id)”")
    }

    // MARK: Opening

    func testOpeningSelectsTheFirstSource() async throws {
        let (model, _, _) = try await opened()
        XCTAssertEqual(model.selectedSourceID, "personal")
        XCTAssertEqual(model.source(for: model.selectedSource)?.calendar, "Personal")
        XCTAssertEqual(model.screen, .settings)
    }

    func testABrokenConfigBlocksTheFormInsteadOfShowingDefaults() {
        let (model, recorder, _) = MenuBarFixture.model()
        recorder.configError = ConfigError.parseFailure("unexpected ]")

        model.openSettings()

        XCTAssertNil(model.editingConfig, "no form full of defaults to overwrite the file with")
        XCTAssertNotNil(model.settingsBlocked)
        XCTAssertNotEqual(model.screen, .settings)
    }

    func testOpeningAsksForTheCalendarChoices() async throws {
        let calendars = [
            CalendarRef(id: "1", title: "Personal", accountTitle: "iCloud", allowsModifications: true),
        ]
        let (model, recorder, _) = try await MenuBarFixture.opened(
            config: MenuBarFixture.twoSources(), calendars: calendars
        )
        XCTAssertEqual(recorder.calendarLookups, 1)
        XCTAssertEqual(model.accountChoices, ["iCloud"])
    }

    // MARK: The detail card follows the selection

    func testSelectingAnotherSourceResolvesToThatSource() async throws {
        let (model, _, _) = try await opened()
        let travel = try handle(model, "travel")

        model.seedSourceIDDraft(for: travel)
        model.selectedSource = travel

        XCTAssertEqual(model.selectedSourceID, "travel")
        XCTAssertEqual(model.source(for: travel)?.calendar, "Travel")
    }

    func testSelectingBackResolvesToTheFirstSourceAgain() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")
        let travel = try handle(model, "travel")

        model.seedSourceIDDraft(for: travel)
        model.seedSourceIDDraft(for: personal)

        XCTAssertEqual(model.selectedSourceID, "personal")
        XCTAssertEqual(model.source(for: model.selectedSource)?.calendar, "Personal")
    }

    func testSelectionSurvivesARenameOfTheSelectedSource() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")

        model.setSourceName("home", of: personal)
        model.commitSourceName(of: personal)

        XCTAssertEqual(model.selectedSourceID, "home")
        XCTAssertEqual(model.source(for: personal)?.calendar, "Personal", "still the same source")
        XCTAssertEqual(model.handle(of: "home"), personal)
    }

    func testSelectingAwayAndBackAcrossARenameStillResolves() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")
        let travel = try handle(model, "travel")

        model.setSourceName("home", of: personal)
        model.commitSourceName(of: personal)
        model.seedSourceIDDraft(for: travel)
        XCTAssertEqual(model.selectedSourceID, "travel")

        model.seedSourceIDDraft(for: personal)
        XCTAssertEqual(model.selectedSourceID, "home")
        XCTAssertEqual(model.source(for: model.selectedSource)?.calendar, "Personal")
    }

    // MARK: Per-source state follows the selection

    func testTheSelectedSourcesRowsAreItsOwn() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")
        let travel = try handle(model, "travel")

        XCTAssertEqual(model.titleFilterRows(.matches, of: personal).map(\.text), ["1:1"])
        XCTAssertEqual(model.titleFilterRows(.matches, of: travel).map(\.text), ["flight", "hotel"])
        XCTAssertTrue(
            Set(model.titleFilterRows(.matches, of: personal).map(\.id))
                .isDisjoint(with: Set(model.titleFilterRows(.matches, of: travel).map(\.id))),
            "two sources' rows must never share an identity"
        )
    }

    func testRowIdentitiesSurviveSwitchingAwayAndBack() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")
        let travel = try handle(model, "travel")
        let before = model.titleFilterRows(.matches, of: personal).map(\.id)

        model.seedSourceIDDraft(for: travel)
        model.seedSourceIDDraft(for: personal)

        XCTAssertEqual(model.titleFilterRows(.matches, of: personal).map(\.id), before)
    }

    func testADraftDoesNotFollowTheUserToAnotherSource() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")
        let travel = try handle(model, "travel")

        model.setTitleFilterDraft(.matches, to: "standup", of: personal)
        XCTAssertEqual(model.titleFilterDraft(.matches, of: personal), "standup")

        model.seedSourceIDDraft(for: travel)
        XCTAssertEqual(model.titleFilterDraft(.matches, of: travel), "")
        XCTAssertEqual(model.titleFilterDraft(.matches, of: personal), "", "retired, not hidden")
    }

    func testADraftSurvivesARenameOfItsOwnSource() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")

        model.setTitleFilterDraft(.matches, to: "standup", of: personal)
        model.setSourceName("home", of: personal)
        model.commitSourceName(of: personal)

        XCTAssertEqual(model.titleFilterDraft(.matches, of: personal), "standup")
    }

    /// Two live sources, so nothing about removal can help: a setter retained
    /// from the source the user left must not take the draft they are typing.
    func testALateFilterSetterFromALiveSourceLeavesTheCurrentDraftAlone() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")
        let travel = try handle(model, "travel")

        model.seedSourceIDDraft(for: travel)
        model.setTitleFilterDraft(.matches, to: "B current draft", of: travel)
        model.setTitleFilterDraft(.matches, to: "late A draft", of: personal)

        XCTAssertEqual(model.titleFilterDraft(.matches, of: travel), "B current draft")
    }

    // MARK: The name field belongs to one source

    func testALateNameSetterRenamesNeitherSource() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")
        let travel = try handle(model, "travel")

        model.seedSourceIDDraft(for: travel)
        model.setSourceName("late-personal-name", of: personal)
        model.commitSourceName(of: personal)

        XCTAssertEqual(model.source(for: personal)?.id, "personal")
        XCTAssertEqual(model.source(for: travel)?.id, "travel")
        XCTAssertEqual(model.sourceName(of: travel), "travel")
    }

    func testALateNameSetterDoesNotStageARenameWarning() async throws {
        let (model, _, _) = try await opened(savedIDs: ["personal", "travel"])
        let personal = try handle(model, "personal")
        let travel = try handle(model, "travel")

        model.seedSourceIDDraft(for: travel)
        model.setSourceName("late-personal-name", of: personal)

        XCTAssertNil(model.pendingRename)
        XCTAssertFalse(model.sourceNameDraft.isDirty)
    }

    func testTheSelectedSourceCanStillBeRenamed() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")

        model.setSourceName("home", of: personal)
        model.commitSourceName(of: personal)

        XCTAssertEqual(model.source(for: personal)?.id, "home")
        XCTAssertEqual(model.selectedSourceID, "home")
    }

    // MARK: Add and remove

    func testAddingASourceDoesNotCarryTheDraftToIt() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")

        model.setTitleFilterDraft(.matches, to: "standup", of: personal)
        model.addSource()

        let added = try XCTUnwrap(model.selectedSource)
        XCTAssertNotEqual(added, personal)
        XCTAssertEqual(model.titleFilterDraft(.matches, of: added), "", "the new source's field starts empty")
    }

    func testSelectingASourceThatWasRemovedResolvesToNothing() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")

        model.removeSelectedSource()

        XCTAssertEqual(model.selectedSourceID, "travel", "the selection falls to what is left")
        XCTAssertNil(model.source(for: personal), "the removed source's handle resolves to nothing")
    }

    func testAStaleSelectionIsANoOpRatherThanANeighbour() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")
        let travel = try handle(model, "travel")
        model.removeSelectedSource()

        model.setTitleFilterDraft(.matches, to: "stale", of: personal)
        model.setSourceName("stale", of: personal)

        XCTAssertEqual(model.titleFilterDraft(.matches, of: personal), "", "a dead handle owns nothing")
        XCTAssertEqual(model.source(for: travel)?.id, "travel", "and the survivor is untouched")
        XCTAssertEqual(model.titleFilterRows(.matches, of: travel).map(\.text), ["flight", "hotel"])
    }

    func testRemovingDoesNotDisturbTheOtherSourcesRows() async throws {
        let (model, _, _) = try await opened()
        let travel = try handle(model, "travel")
        let before = model.titleFilterRows(.matches, of: travel).map(\.id)

        model.removeSelectedSource()

        XCTAssertEqual(model.titleFilterRows(.matches, of: travel).map(\.id), before)
    }

    /// A removed source's id can be taken by a later one. The old handle must
    /// resolve to nothing, never to the replacement.
    func testAStaleHandleDoesNotReachASourceThatReusedItsID() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")
        model.removeSelectedSource()

        model.addSource()
        let replacement = try XCTUnwrap(model.selectedSource)
        model.setSourceName("personal", of: replacement)
        model.commitSourceName(of: replacement)
        XCTAssertEqual(model.source(for: replacement)?.id, "personal")

        model.updateSource(personal) { $0.titleTemplate = "hijacked" }
        XCTAssertNotEqual(model.source(for: replacement)?.titleTemplate, "hijacked")
        XCTAssertNil(model.source(for: personal))
    }

    /// Closing and reopening is a new editing session: a handle from the last
    /// one must not resolve into this one.
    func testAHandleFromTheLastSessionDoesNotResolve() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")

        model.closeSettings()
        model.openSettings()
        await model.calendarChoicesTask?.value

        XCTAssertNil(model.source(for: personal))
        XCTAssertNotNil(model.handle(of: "personal"), "the reopened session has its own")
    }
}
