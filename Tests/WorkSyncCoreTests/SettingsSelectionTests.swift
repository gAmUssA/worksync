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
    var renameError: String?
    /// The orphan-warning alert, held the way the model holds it — round 9's
    /// harness returned `.awaitingConfirmation` without storing anything, so its
    /// test judged a dirty draft twice rather than an open alert.
    var pendingRename: (source: SourceHandle, to: String)?
    /// Ids already on disk, so a rename of a saved source needs confirming.
    var savedSourceIDs: Set<String> = []

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
    /// `MenuBarModel.select`, which now stops on a refusal rather than moving
    /// past it.
    mutating func select(_ handle: SourceHandle?, keepingDrafts: Bool = false, committing: Bool = false) {
        if committing, commit().blocksAction {
            selected = nameField.pending?.handle
            return
        }
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

    /// `MenuBarModel.commitSourceIDDraft` — the whole of it, including what it
    /// now reports back.
    mutating func commit() -> SourceNameCommit {
        // An open confirmation outranks the field's current text.
        if pendingRename != nil {
            return .awaitingConfirmation
        }
        guard let pending = nameField.pending,
              let source = handles.resolve(pending.handle) else { return .settled }
        let others = config.sources.map(\.id).filter { $0 != source.id }

        switch pending.draft.commit(savedSourceIDs: savedSourceIDs, otherSourceIDs: others) {
        case .unchanged:
            renameError = nil
            nameField.revert()
            return .settled
        case let .rejected(reason):
            renameError = reason
            return .rejected(reason: reason)
        case let .apply(newID):
            renameError = nil
            rename(pending.handle, to: newID)
            return .renamed(newID)
        case let .confirm(_, to):
            renameError = nil
            pendingRename = (pending.handle, to)
            return .awaitingConfirmation
        }
    }

    /// `MenuBarModel.commitSourceName` — the field's own submit.
    mutating func commitName(of handle: SourceHandle) {
        guard nameField.draft(of: handle) != nil else { return }
        _ = commit()
    }

    /// `MenuBarModel.confirmPendingRename`
    mutating func confirmRename() {
        guard let pending = pendingRename else { return }
        pendingRename = nil
        rename(pending.source, to: pending.to)
    }

    /// `MenuBarModel.cancelPendingRename`
    mutating func cancelRename() {
        pendingRename = nil
        nameField.revert()
    }

    /// `MenuBarModel.addSource`, which stops on a refusal or an open alert
    /// whatever the field currently says.
    mutating func addSource() {
        if commit().blocksAction {
            return
        }
        let added = SourceConfig(id: "source-2", account: "iCloud", calendar: "C")
        config.sources.append(added)
        select(handles.mint(added.id))
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

    /// Both sources already on disk, so renaming one orphans its events and has
    /// to be confirmed.
    private func saved() throws -> Editor {
        var editor = try Editor(ConfigLoader.parse(Self.fixture))
        editor.savedSourceIDs = ["personal", "travel"]
        return editor
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

    // MARK: A refused name stops what it was asked to do

    /// `+` used to commit, ignore the refusal, and add anyway — clearing the
    /// error on the way. `saveSettings` already stopped; now they agree.
    func testAddingASourceIsBlockedWhileTheNameIsInvalid() throws {
        var editor = try editor()
        let personal = try XCTUnwrap(editor.handle("personal"))

        editor.type(name: "team/personal", into: personal) // "/" corrupts markers
        editor.addSource()

        XCTAssertEqual(editor.config.sources.count, 2, "no source may be added")
        XCTAssertNotNil(editor.renameError, "and the reason must still be on screen")
        XCTAssertEqual(editor.name(of: personal), "team/personal", "with the typed name still in the field")
    }

    func testAddingASourceProceedsOnceTheNameIsValid() throws {
        var editor = try editor()
        let personal = try XCTUnwrap(editor.handle("personal"))

        editor.type(name: "home", into: personal)
        editor.addSource()

        XCTAssertEqual(editor.config.sources.count, 3)
        XCTAssertEqual(editor.source(for: personal)?.id, "home", "the rename landed first")
        XCTAssertNil(editor.renameError)
    }

    /// The comment promising the draft is not lost used to be false: switching
    /// rows discarded the typed name AND the error. Now the move does not
    /// happen until the name can be applied.
    func testSelectingAnotherSourceIsBlockedWhileTheNameIsInvalid() throws {
        var editor = try editor()
        let personal = try XCTUnwrap(editor.handle("personal"))
        let travel = try XCTUnwrap(editor.handle("travel"))

        editor.type(name: "team/personal", into: personal)
        editor.select(travel, committing: true)

        XCTAssertEqual(editor.selected, personal, "the selection stays on the source with the problem")
        XCTAssertEqual(editor.name(of: personal), "team/personal", "the typed name survives")
        XCTAssertNotNil(editor.renameError, "and so does the reason")
    }

    func testSelectingAnotherSourceProceedsOnceTheNameIsValid() throws {
        var editor = try editor()
        let personal = try XCTUnwrap(editor.handle("personal"))
        let travel = try XCTUnwrap(editor.handle("travel"))

        editor.type(name: "home", into: personal)
        editor.select(travel, committing: true)

        XCTAssertEqual(editor.selected, travel)
        XCTAssertEqual(editor.source(for: personal)?.id, "home", "the rename landed on the way out")
        XCTAssertNil(editor.renameError)
    }

    // MARK: An open confirmation

    /// A rename that orphans events opens a confirmation. Whatever asked for the
    /// commit stops too — the alert names one source, and anything that followed
    /// would happen behind it.
    func testAnOpenConfirmationStopsTheAction() throws {
        var editor = try saved()
        let personal = try XCTUnwrap(editor.handle("personal"))
        let travel = try XCTUnwrap(editor.handle("travel"))

        editor.type(name: "home", into: personal)
        XCTAssertEqual(editor.commit(), .awaitingConfirmation)
        XCTAssertNotNil(editor.pendingRename)

        editor.select(travel, committing: true)
        XCTAssertEqual(editor.selected, personal, "the selection waits for the answer")

        editor.addSource()
        XCTAssertEqual(editor.config.sources.count, 2, "and so does the add")
    }

    /// The defect: the block was reached only when the field was dirty, so a
    /// retained setter putting the original name back left the alert open and
    /// the guard asleep.
    func testAnOpenConfirmationStillBlocksAfterTheNameIsRestored() throws {
        var editor = try saved()
        let personal = try XCTUnwrap(editor.handle("personal"))
        let travel = try XCTUnwrap(editor.handle("travel"))

        editor.type(name: "home", into: personal)
        XCTAssertEqual(editor.commit(), .awaitingConfirmation)

        // A retained setter for the same live source restores the old name. The
        // field is clean again; the alert has not been answered.
        editor.type(name: "personal", into: personal)
        XCTAssertFalse(editor.nameField.isDirty, "the field agrees with the config again")
        XCTAssertNotNil(editor.pendingRename, "but the alert is still on screen")

        XCTAssertEqual(editor.commit(), .awaitingConfirmation, "the commit must report the alert, not the text")

        editor.addSource()
        XCTAssertEqual(editor.config.sources.count, 2, "no source may be added behind it")

        editor.select(travel, committing: true)
        XCTAssertEqual(editor.selected, personal, "and the selection may not move")
    }

    func testCancellingTheConfirmationLetsTheActionProceed() throws {
        var editor = try saved()
        let personal = try XCTUnwrap(editor.handle("personal"))
        let travel = try XCTUnwrap(editor.handle("travel"))

        editor.type(name: "home", into: personal)
        XCTAssertEqual(editor.commit(), .awaitingConfirmation)

        editor.cancelRename()
        XCTAssertNil(editor.pendingRename)
        XCTAssertEqual(editor.name(of: personal), "personal", "cancelling puts the old name back")

        editor.select(travel, committing: true)
        XCTAssertEqual(editor.selected, travel, "the move goes through")
        XCTAssertEqual(editor.source(for: personal)?.id, "personal", "and nothing was renamed")
    }

    func testConfirmingTheRenameLetsTheActionProceed() throws {
        var editor = try saved()
        let personal = try XCTUnwrap(editor.handle("personal"))

        editor.type(name: "home", into: personal)
        XCTAssertEqual(editor.commit(), .awaitingConfirmation)

        editor.confirmRename()
        XCTAssertNil(editor.pendingRename)
        XCTAssertEqual(editor.source(for: personal)?.id, "home", "the id changed")
        XCTAssertEqual(editor.handles.id(of: personal), "home", "the handle names it")
        XCTAssertEqual(editor.name(of: personal), "home", "and the field shows it")

        editor.addSource()
        XCTAssertEqual(editor.config.sources.count, 3, "the add goes through once the alert is answered")
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
