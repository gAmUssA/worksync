import WorkSyncCore
import XCTest
@testable import worksync

/// The title-filter rows and add fields, against the real model.
@MainActor
final class SettingsTitleFilterTests: XCTestCase {
    private func opened() async throws
        -> (model: MenuBarModel, recorder: MenuBarRecorder, observer: FakeChangeObserver) {
        try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
    }

    private func handle(_ model: MenuBarModel, _ id: String) throws -> SourceHandle {
        try XCTUnwrap(model.handle(of: id))
    }

    // MARK: Rows keep their identity

    /// `[one, two, three]`, remove the first, then a text field still live for
    /// the third commits. By position it would write to what shifted into that
    /// slot; by identity it follows the row it belongs to.
    func testALateRowCommitFollowsItsOwnRow() async throws {
        let (model, _, _) = try await opened()
        let travel = try handle(model, "travel")
        model.addTitleFilter(.matches, to: travel) // draft is empty: no-op
        model.setTitleFilterDraft(.matches, to: "train", of: travel)
        model.addTitleFilter(.matches, to: travel)
        XCTAssertEqual(model.titleFilterRows(.matches, of: travel).map(\.text), ["flight", "hotel", "train"])

        let rows = model.titleFilterRows(.matches, of: travel)
        let third = rows[2].id
        model.removeTitleFilter(.matches, from: travel, row: rows[0].id)

        model.setTitleFilterEntry("TRAIN", .matches, of: travel, row: third)
        XCTAssertEqual(model.titleFilterRows(.matches, of: travel).map(\.text), ["hotel", "TRAIN"])
    }

    func testACommitForARemovedRowChangesNothing() async throws {
        let (model, _, _) = try await opened()
        let travel = try handle(model, "travel")
        let rows = model.titleFilterRows(.matches, of: travel)

        model.removeTitleFilter(.matches, from: travel, row: rows[0].id)
        model.setTitleFilterEntry("late", .matches, of: travel, row: rows[0].id)

        XCTAssertEqual(model.titleFilterRows(.matches, of: travel).map(\.text), ["hotel"])
    }

    func testTwoRowsHoldingTheSameTextStayTwoRows() async throws {
        let (model, _, _) = try await opened()
        let travel = try handle(model, "travel")
        let rows = model.titleFilterRows(.matches, of: travel)

        model.setTitleFilterEntry("flight", .matches, of: travel, row: rows[1].id)
        let duplicated = model.titleFilterRows(.matches, of: travel)
        XCTAssertEqual(duplicated.map(\.text), ["flight", "flight"])
        XCTAssertNotEqual(duplicated[0].id, duplicated[1].id)

        model.removeTitleFilter(.matches, from: travel, row: duplicated[0].id)
        XCTAssertEqual(model.titleFilterRows(.matches, of: travel).map(\.text), ["flight"])
        XCTAssertEqual(model.titleFilterRows(.matches, of: travel)[0].id, duplicated[1].id)
    }

    // MARK: An emptied row

    func testAnEmptiedRowExplainsItselfAndBlocksTheSave() async throws {
        let (model, recorder, _) = try await opened()
        let personal = try handle(model, "personal")
        let row = try XCTUnwrap(model.titleFilterRows(.matches, of: personal).first)

        model.setTitleFilterEntry("", .matches, of: personal, row: row.id)

        XCTAssertNotNil(model.titleFilterRowMessage(.matches, of: personal, row: row.id))
        XCTAssertNotNil(model.titleFilterProblem, "Save is disabled, with a reason")
        model.saveSettings()
        XCTAssertTrue(recorder.savedConfigs.isEmpty, "the writer is never called")

        model.setTitleFilterEntry("1:1", .matches, of: personal, row: row.id)
        XCTAssertNil(model.titleFilterRowMessage(.matches, of: personal, row: row.id))
        XCTAssertNil(model.titleFilterProblem)
    }

    func testAWhitespaceOnlyRowIsRefusedToo() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")
        let row = try XCTUnwrap(model.titleFilterRows(.matches, of: personal).first)

        model.setTitleFilterEntry("   ", .matches, of: personal, row: row.id)
        XCTAssertNotNil(model.titleFilterRowMessage(.matches, of: personal, row: row.id))
    }

    /// The footer shows one message. A validation problem the user can act on
    /// now outranks a write error from a save that already failed.
    func testTheLiveProblemOutranksAStaleWriteError() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")
        model.saveError = "Could not write config: permission denied"

        let row = try XCTUnwrap(model.titleFilterRows(.matches, of: personal).first)
        model.setTitleFilterEntry("", .matches, of: personal, row: row.id)

        XCTAssertEqual(
            SettingsMessagePolicy.footerMessage(
                validationProblem: model.titleFilterProblem, saveError: model.saveError
            ),
            model.titleFilterProblem
        )
    }

    // MARK: The add field

    func testAddingTrimsAndRefusesBlanksAndDuplicates() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")

        model.setTitleFilterDraft(.matches, to: "  standup  ", of: personal)
        model.addTitleFilter(.matches, to: personal)
        XCTAssertEqual(model.titleFilterRows(.matches, of: personal).map(\.text), ["1:1", "standup"])
        XCTAssertEqual(model.titleFilterDraft(.matches, of: personal), "", "the field clears once it lands")

        model.setTitleFilterDraft(.matches, to: "   ", of: personal)
        model.addTitleFilter(.matches, to: personal)
        XCTAssertEqual(model.titleFilterRows(.matches, of: personal).count, 2, "blank is refused")

        model.setTitleFilterDraft(.matches, to: "STANDUP", of: personal)
        model.addTitleFilter(.matches, to: personal)
        XCTAssertEqual(
            model.titleFilterRows(.matches, of: personal).count, 2,
            "a case-different duplicate is one filter written twice"
        )
        XCTAssertNotNil(model.titleFilterProblem, "and the reason is on screen")
    }

    func testAnEntryContainingACommaIsOneEntry() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")

        model.setTitleFilterDraft(.matches, to: "Lunch, then gym", of: personal)
        model.addTitleFilter(.matches, to: personal)

        XCTAssertEqual(
            model.titleFilterRows(.matches, of: personal).map(\.text), ["1:1", "Lunch, then gym"],
            "a calendar title can contain a comma, which is why this is a list and not one field"
        )
    }

    /// A retained "+" from one source must add to that source, and clear only
    /// that source's field.
    func testAddingToOneSourceLeavesTheOtherAlone() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")
        let travel = try handle(model, "travel")

        model.seedSourceIDDraft(for: travel)
        model.setTitleFilterDraft(.matches, to: "B draft", of: travel)
        model.setTitleFilterDraft(.matches, to: "A draft", of: personal)

        model.addTitleFilter(.matches, to: personal)

        XCTAssertEqual(model.titleFilterRows(.matches, of: personal).map(\.text), ["1:1", "A draft"])
        XCTAssertEqual(model.titleFilterRows(.matches, of: travel).map(\.text), ["flight", "hotel"])
        XCTAssertEqual(model.titleFilterDraft(.matches, of: travel), "B draft", "B's field is untouched")
    }

    func testTheTwoListsAreIndependent() async throws {
        let (model, _, _) = try await opened()
        let personal = try handle(model, "personal")

        model.setTitleFilterDraft(.excludes, to: "tentative", of: personal)
        model.addTitleFilter(.excludes, to: personal)

        XCTAssertEqual(model.titleFilterRows(.excludes, of: personal).map(\.text), ["tentative"])
        XCTAssertEqual(model.titleFilterRows(.matches, of: personal).map(\.text), ["1:1"])
    }
}
