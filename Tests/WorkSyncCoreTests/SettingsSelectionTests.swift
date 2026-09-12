import XCTest
@testable import WorkSyncCore

/// Switching between sources in the settings form.
///
/// `MenuBarModel` lives in the `worksync` executable target, and the package
/// declares one test target, on `WorkSyncCore` — so nothing here imports the
/// model. `Editor` below mirrors the model's composition for these operations,
/// line for line, and the report names what that leaves uncovered: the model's
/// own two- and three-line wrappers, and whether a row click writes the binding
/// at all.
///
/// What these tests do establish is the rule underneath: an identity-addressed
/// selection resolves to its own source, keeps doing so across a rename, takes
/// its per-source state with it, and resolves to nothing once its source is
/// removed.
private struct Editor {
    var config: Config
    var handles = SourceHandles()
    var selected: SourceHandle?
    var drafts = TitleFilterDrafts()
    var rowIDs = TitleFilterRowIDs()
    var nameField = SourceNameDraft()

    /// `MenuBarModel.openSettings`
    init(_ config: Config) {
        self.config = config
        handles.seed(config.sources.map(\.id))
        for source in config.sources {
            guard let handle = handles.handle(of: source.id) else { continue }
            rowIDs.seed(list(handle), count: source.titleMatches.count)
        }
        select(config.sources.first.flatMap { handles.handle(of: $0.id) })
    }

    func list(_ handle: SourceHandle) -> TitleFilterRowIDs.List {
        TitleFilterRowIDs.List(source: handle, field: "matches")
    }

    /// `MenuBarModel.selectedSourceID`
    var selectedSourceID: String? {
        handles.resolve(selected)?.id
    }

    /// `MenuBarModel.source(for:)`
    func source(for handle: SourceHandle?) -> SourceConfig? {
        guard let id = handles.resolve(handle)?.id else { return nil }
        return config.sources.first { $0.id == id }
    }

    func handle(_ id: String) -> SourceHandle? {
        handles.handle(of: id)
    }

    /// `MenuBarModel.select(_:)` — the selection funnel, which retires the
    /// per-source drafts unless the move is a rename.
    mutating func select(_ handle: SourceHandle?, keepingDrafts: Bool = false) {
        selected = handle
        nameField.seed(handle, id: handles.resolve(handle)?.id)
        if !keepingDrafts {
            drafts.removeAll()
        }
    }

    /// `MenuBarModel.applyRename`
    mutating func rename(_ handle: SourceHandle, to newID: String) {
        guard let oldID = handles.id(of: handle),
              let index = config.sources.firstIndex(where: { $0.id == oldID }) else { return }
        config.sources[index].id = newID
        handles.rename(handle, to: newID)
        select(handle, keepingDrafts: true)
    }

    /// `MenuBarModel.removeSelectedSource`
    mutating func removeSelected() {
        guard let source = handles.resolve(selected),
              let index = config.sources.firstIndex(where: { $0.id == source.id }) else { return }
        config.sources.remove(at: index)
        rowIDs.removeSource(source.handle)
        handles.remove(source.handle)
        select(config.sources.first.flatMap { handles.handle(of: $0.id) })
    }

    /// `MenuBarModel.sourceName` / `setSourceName`
    func name(of handle: SourceHandle) -> String {
        nameField.text(of: handle, fallback: handles.id(of: handle) ?? "")
    }

    mutating func type(name text: String, into handle: SourceHandle) {
        guard handles.id(of: handle) != nil else { return }
        nameField.setText(text, of: handle)
    }

    /// `MenuBarModel.commitSourceName` + the `.apply` arm of
    /// `commitSourceIDDraft`. Unsaved sources rename without a warning.
    mutating func commitName(of handle: SourceHandle) {
        guard let draft = nameField.draft(of: handle),
              let source = handles.resolve(handle) else { return }
        let others = config.sources.map(\.id).filter { $0 != source.id }
        if case let .apply(newID) = draft.commit(savedSourceIDs: [], otherSourceIDs: others) {
            rename(handle, to: newID)
        }
    }

    /// `MenuBarModel.titleFilterDraft` / `setTitleFilterDraft`
    func draft(of handle: SourceHandle?) -> String {
        drafts.text("matches", of: handle)
    }

    mutating func type(_ text: String, into handle: SourceHandle) {
        drafts.setText(text, "matches", of: handle, in: handles)
    }

    /// `MenuBarModel.titleFilterRows`
    func rows(of handle: SourceHandle) -> [TitleFilterRow] {
        rowIDs.rows(list(handle), entries: source(for: handle)?.titleMatches ?? [])
    }
}

final class SettingsSelectionTests: XCTestCase {
    private static let fixture = """
    [target]
    account = "Work"
    calendar = "Calendar"

    [[source]]
    id = "personal"
    account = "iCloud"
    calendar = "Personal"
    title_matches = ["1:1"]

    [[source]]
    id = "travel"
    account = "Google"
    calendar = "Travel"
    title_matches = ["flight", "hotel"]
    """

    private func editor() throws -> Editor {
        try Editor(ConfigLoader.parse(Self.fixture))
    }

    // MARK: The detail card follows the selection

    func testOpeningSelectsTheFirstSource() throws {
        let editor = try editor()
        XCTAssertEqual(editor.source(for: editor.selected)?.id, "personal")
        XCTAssertEqual(editor.selectedSourceID, "personal")
    }

    func testSelectingAnotherSourceResolvesToThatSource() throws {
        var editor = try editor()
        let travel = try XCTUnwrap(editor.handle("travel"))

        editor.select(travel)
        let selected = try XCTUnwrap(editor.source(for: editor.selected))
        XCTAssertEqual(selected.id, "travel")
        XCTAssertEqual(selected.calendar, "Travel", "the card must show that source's own fields")
        XCTAssertEqual(editor.selectedSourceID, "travel")
    }

    func testSelectingBackResolvesToTheFirstSourceAgain() throws {
        var editor = try editor()
        let personal = try XCTUnwrap(editor.handle("personal"))
        let travel = try XCTUnwrap(editor.handle("travel"))

        editor.select(travel)
        editor.select(personal)
        XCTAssertEqual(editor.source(for: editor.selected)?.calendar, "Personal")
        XCTAssertEqual(editor.selectedSourceID, "personal")
    }

    /// The reason the selection is an identity: a rename changes the id the
    /// selection would otherwise have been holding.
    func testSelectionSurvivesARenameOfTheSelectedSource() throws {
        var editor = try editor()
        let personal = try XCTUnwrap(editor.handle("personal"))

        editor.rename(personal, to: "home")
        XCTAssertEqual(editor.selectedSourceID, "home", "the derived id follows the rename")
        XCTAssertEqual(editor.source(for: editor.selected)?.calendar, "Personal", "still the same source")
        XCTAssertEqual(editor.source(for: personal)?.id, "home", "and the captured handle still finds it")
    }

    func testSelectingAwayAndBackAcrossARenameStillResolves() throws {
        var editor = try editor()
        let personal = try XCTUnwrap(editor.handle("personal"))
        let travel = try XCTUnwrap(editor.handle("travel"))

        editor.rename(personal, to: "home")
        editor.select(travel)
        XCTAssertEqual(editor.selectedSourceID, "travel")

        editor.select(personal)
        XCTAssertEqual(editor.selectedSourceID, "home")
        XCTAssertEqual(editor.source(for: editor.selected)?.calendar, "Personal")
    }

    // MARK: Per-source state follows the selection

    func testTheSelectedSourcesRowsAreItsOwn() throws {
        var editor = try editor()
        let personal = try XCTUnwrap(editor.handle("personal"))
        let travel = try XCTUnwrap(editor.handle("travel"))

        XCTAssertEqual(editor.rows(of: personal).map(\.text), ["1:1"])

        editor.select(travel)
        XCTAssertEqual(editor.rows(of: travel).map(\.text), ["flight", "hotel"])
        XCTAssertNotEqual(
            Set(editor.rows(of: travel).map(\.id)), Set(editor.rows(of: personal).map(\.id)),
            "two sources' rows must never share an identity"
        )
    }

    func testRowIdentitiesSurviveSwitchingAwayAndBack() throws {
        var editor = try editor()
        let personal = try XCTUnwrap(editor.handle("personal"))
        let travel = try XCTUnwrap(editor.handle("travel"))
        let before = editor.rows(of: personal).map(\.id)

        editor.select(travel)
        editor.select(personal)
        XCTAssertEqual(editor.rows(of: personal).map(\.id), before)
    }

    func testADraftDoesNotFollowTheUserToAnotherSource() throws {
        var editor = try editor()
        let personal = try XCTUnwrap(editor.handle("personal"))
        let travel = try XCTUnwrap(editor.handle("travel"))

        editor.type("standup", into: personal)
        XCTAssertEqual(editor.draft(of: personal), "standup")

        editor.select(travel)
        XCTAssertEqual(editor.draft(of: travel), "", "the new source's field starts empty")
        XCTAssertEqual(editor.draft(of: personal), "", "and the old text is retired, not hidden")
    }

    func testADraftSurvivesARenameOfItsOwnSource() throws {
        var editor = try editor()
        let personal = try XCTUnwrap(editor.handle("personal"))

        editor.type("standup", into: personal)
        editor.rename(personal, to: "home")
        XCTAssertEqual(editor.draft(of: personal), "standup", "a rename is not a change of source")
        XCTAssertEqual(editor.draft(of: editor.selected), "standup")
    }

    // MARK: The name field belongs to one source

    /// The reviewer's reproduction, in order: retain A's name setter, select B,
    /// deliver A's setter, commit. A must not be renamed, and neither must B.
    func testALateNameSetterRenamesNeitherSource() throws {
        var editor = try editor()
        let personal = try XCTUnwrap(editor.handle("personal"))
        let travel = try XCTUnwrap(editor.handle("travel"))

        editor.select(travel)
        editor.type(name: "late-personal-name", into: personal)
        editor.commitName(of: personal)

        XCTAssertEqual(editor.source(for: personal)?.id, "personal", "A keeps its name")
        XCTAssertEqual(editor.source(for: travel)?.id, "travel", "and B is not renamed to A's text")
        XCTAssertEqual(editor.name(of: travel), "travel", "B's field shows B's own name")
    }

    func testALateNameSetterDoesNotStageARenameWarning() throws {
        var editor = try editor()
        let personal = try XCTUnwrap(editor.handle("personal"))
        let travel = try XCTUnwrap(editor.handle("travel"))

        editor.select(travel)
        editor.type(name: "late-personal-name", into: personal)

        // Nothing to commit means nothing to warn about: the field belongs to
        // travel, which has not been touched.
        XCTAssertNil(editor.nameField.draft(of: personal))
        XCTAssertFalse(editor.nameField.isDirty)
    }

    func testTheSelectedSourceCanStillBeRenamed() throws {
        var editor = try editor()
        let personal = try XCTUnwrap(editor.handle("personal"))

        editor.type(name: "home", into: personal)
        editor.commitName(of: personal)
        XCTAssertEqual(editor.source(for: personal)?.id, "home")
        XCTAssertEqual(editor.selectedSourceID, "home")
    }

    /// A filter draft typed into the source on screen survives a late setter
    /// from a source the user has left — both are live, so nothing about
    /// removal can help here.
    func testALateFilterSetterFromALiveSourceLeavesTheCurrentDraftAlone() throws {
        var editor = try editor()
        let personal = try XCTUnwrap(editor.handle("personal"))
        let travel = try XCTUnwrap(editor.handle("travel"))

        editor.select(travel)
        editor.type("B current draft", into: travel)
        editor.type("late A draft", into: personal)

        XCTAssertEqual(editor.draft(of: travel), "B current draft")
    }

    // MARK: A removed source

    func testSelectingASourceThatWasRemovedResolvesToNothing() throws {
        var editor = try editor()
        let personal = try XCTUnwrap(editor.handle("personal"))

        editor.removeSelected()
        XCTAssertEqual(editor.selectedSourceID, "travel", "the selection falls to what is left")
        XCTAssertNil(editor.source(for: personal), "the removed source's handle resolves to nothing")
        XCTAssertNil(editor.handles.id(of: personal))
    }

    /// A control still holding the removed source's handle must resolve to
    /// nothing — never to the source that took its place in the list, and never
    /// to one that later takes its id.
    func testAStaleSelectionIsANoOpRatherThanANeighbour() throws {
        var editor = try editor()
        let personal = try XCTUnwrap(editor.handle("personal"))
        editor.removeSelected()

        editor.select(personal)
        XCTAssertNil(editor.source(for: editor.selected))
        XCTAssertNil(editor.selectedSourceID)

        editor.type("stale", into: personal)
        XCTAssertEqual(editor.draft(of: personal), "", "a dead handle owns nothing")
        XCTAssertEqual(
            try editor.rows(of: XCTUnwrap(editor.handle("travel"))).map(\.text), ["flight", "hotel"],
            "and the surviving source is untouched"
        )
    }

    func testRemovingDoesNotDisturbTheOtherSourcesRows() throws {
        var editor = try editor()
        let travel = try XCTUnwrap(editor.handle("travel"))
        let before = editor.rows(of: travel).map(\.id)

        editor.removeSelected()
        XCTAssertEqual(editor.rows(of: travel).map(\.id), before)
    }
}
