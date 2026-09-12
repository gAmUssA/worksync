import WorkSyncCore
import XCTest
@testable import worksync

/// Reordering, through the real `moveSources` — the array `move`, not just the
/// predicate that guards it. Order decides cross-source dedup (SPEC §5 step 5),
/// so moving the wrong source changes which one supplies a shared event's
/// blocker.
@MainActor
final class SettingsOrderTests: XCTestCase {
    private func fourSources() async throws -> MenuBarModel {
        let config = try ConfigLoader.parse("""
        [target]
        account = "Work"
        calendar = "Calendar"

        [[source]]
        id = "a"
        account = "iCloud"
        calendar = "A"

        [[source]]
        id = "b"
        account = "iCloud"
        calendar = "B"

        [[source]]
        id = "c"
        account = "iCloud"
        calendar = "C"

        [[source]]
        id = "d"
        account = "iCloud"
        calendar = "D"
        """)
        let (model, _, _) = await MenuBarFixture.opened(config: config)
        return model
    }

    private func order(_ model: MenuBarModel) -> [String] {
        model.editingConfig?.sources.map(\.id) ?? []
    }

    func testAnOrdinaryDragReordersTheList() async throws {
        let model = try await fourSources()
        let rendered = model.sourceRows.map(\.id)

        model.moveSources(from: IndexSet(integer: 1), to: 4, rendered: rendered)

        XCTAssertEqual(order(model), ["a", "c", "d", "b"])
    }

    func testDraggingUpwardsReordersTheList() async throws {
        let model = try await fourSources()
        model.moveSources(from: IndexSet(integer: 3), to: 0, rendered: model.sourceRows.map(\.id))
        XCTAssertEqual(order(model), ["d", "a", "b", "c"])
    }

    func testAMultipleSelectionMovesTogether() async throws {
        let model = try await fourSources()
        model.moveSources(from: IndexSet([0, 2]), to: 4, rendered: model.sourceRows.map(\.id))
        XCTAssertEqual(order(model), ["b", "d", "a", "c"])
    }

    /// The drop was drawn on `[a,b,c,D]`; by the time it lands `a` is gone.
    /// Offsets (1,3) still fit `[b,c,d]` — and name `c`, which nobody dragged.
    func testADropDrawnOnAListThatLostASourceIsRejected() async throws {
        let model = try await fourSources()
        let rendered = model.sourceRows.map(\.id)

        model.removeSelectedSource() // removes "a", the selected first source
        XCTAssertEqual(order(model), ["b", "c", "d"])

        model.moveSources(from: IndexSet(integer: 1), to: 3, rendered: rendered)

        XCTAssertEqual(order(model), ["b", "c", "d"], "the stale drop changes nothing")
    }

    func testADropDrawnBeforeAReorderIsRejected() async throws {
        let model = try await fourSources()
        let rendered = model.sourceRows.map(\.id)

        model.moveSources(from: IndexSet(integer: 0), to: 4, rendered: rendered)
        XCTAssertEqual(order(model), ["b", "c", "d", "a"])

        // A second drop still carrying the original order.
        model.moveSources(from: IndexSet(integer: 0), to: 2, rendered: rendered)
        XCTAssertEqual(order(model), ["b", "c", "d", "a"], "unchanged")
    }

    func testADropIsRejectedWhenASourceWasReplacedByItsNamesake() async throws {
        let model = try await fourSources()
        let rendered = model.sourceRows.map(\.id)

        model.removeSelectedSource()
        model.addSource()
        let replacement = try XCTUnwrap(model.selectedSource)
        model.setSourceName("a", of: replacement)
        model.commitSourceName(of: replacement)

        model.moveSources(from: IndexSet(integer: 0), to: 2, rendered: rendered)

        XCTAssertEqual(
            order(model), ["b", "c", "d", "a"],
            "the same names are not the same rows"
        )
    }

    func testAnOutOfRangeDropChangesNothingAndDoesNotTrap() async throws {
        let model = try await fourSources()
        let rendered = model.sourceRows.map(\.id)

        model.moveSources(from: IndexSet(integer: 9), to: 0, rendered: rendered)
        model.moveSources(from: IndexSet(integer: 0), to: 9, rendered: rendered)
        model.moveSources(from: IndexSet(), to: 0, rendered: rendered)

        XCTAssertEqual(order(model), ["a", "b", "c", "d"])
    }

    /// An unrelated edit does not change which rows exist, so a drop drawn
    /// before it is still meaningful.
    func testAnUnrelatedFieldEditDoesNotInvalidateADrag() async throws {
        let model = try await fourSources()
        let rendered = model.sourceRows.map(\.id)
        let a = try XCTUnwrap(model.handle(of: "a"))

        model.updateSource(a) { $0.titleTemplate = "Busy" }
        model.moveSources(from: IndexSet(integer: 0), to: 4, rendered: rendered)

        XCTAssertEqual(order(model), ["b", "c", "d", "a"])
    }
}
