import Foundation

/// One row of a title-filter list, carrying an identity the list itself does
/// not have.
public struct TitleFilterRow: Identifiable, Equatable {
    public let id: TitleFilterRowID
    public let text: String

    public init(id: TitleFilterRowID, text: String) {
        self.id = id
        self.text = text
    }
}

/// How a row is addressed.
public enum TitleFilterRowID: Hashable {
    /// Minted for the row and kept until the row is removed.
    case stable(UUID)
    /// No identity was seeded for this list, so the row is addressed the old
    /// way. Stable across renders, which is what SwiftUI needs, but it shifts
    /// under a removal exactly as a raw index does.
    case position(Int)
}

/// Identities for the rows of each title-filter list, held for as long as the
/// settings form is open.
///
/// A row's position is not its identity. Remove row 0 of `[A, B, C]` and every
/// later row shifts up; a text field still live for the old row 1 then commits
/// with index 1, which is now C. The range check passes, so nothing traps and
/// nothing is logged — the user just finds the wrong entry rewritten. That is
/// worse than the crash the same shape caused for sources, because it is
/// silent.
///
/// The text is not identity either: two rows can legitimately hold the same
/// string while one of them is being typed, which is why the form could not
/// simply key rows by their value.
///
/// So identity is minted here, lives in the editing session, and dies with the
/// row. A commit that arrives for a row that is gone resolves to nothing and is
/// dropped; a commit for a row that merely moved resolves to where it moved.
///
/// `[String]` is the right shape for the config file — this exists only for as
/// long as a human is editing one.
public struct TitleFilterRowIDs: Equatable {
    /// Which list a row belongs to: one source, one field.
    public struct List: Hashable {
        public let source: String
        public let field: String

        public init(source: String, field: String) {
            self.source = source
            self.field = field
        }
    }

    private var ids: [List: [UUID]] = [:]

    public init() {}

    /// Gives every row of `list` an identity. Idempotent while the count holds:
    /// seeding a list that already matches leaves its identities alone, so a
    /// re-seed cannot silently re-key rows under a live text field.
    public mutating func seed(_ list: List, count: Int) {
        guard ids[list]?.count != count else { return }
        ids[list] = (0 ..< count).map { _ in UUID() }
    }

    /// `entries` paired with their identities.
    ///
    /// Pure — rendering must not mint anything. A list nobody seeded falls back
    /// to positional ids, which is exactly the behaviour that existed before
    /// this type: no worse, and visible in a test.
    public func rows(_ list: List, entries: [String]) -> [TitleFilterRow] {
        guard let identities = ids[list], identities.count == entries.count else {
            return entries.indices.map { TitleFilterRow(id: .position($0), text: entries[$0]) }
        }
        return entries.indices.map { TitleFilterRow(id: .stable(identities[$0]), text: entries[$0]) }
    }

    /// Where `id` sits now, or nil if that row is gone.
    public func position(of id: TitleFilterRowID, in list: List, count: Int) -> Int? {
        switch id {
        case let .position(index):
            return (0 ..< count).contains(index) ? index : nil
        case let .stable(uuid):
            guard let index = ids[list]?.firstIndex(of: uuid), index < count else { return nil }
            return index
        }
    }

    /// Records a row appended to the end of `list`.
    public mutating func appended(to list: List) {
        ids[list, default: []].append(UUID())
    }

    /// Records a row removed from `list`.
    public mutating func removed(at index: Int, from list: List) {
        guard var identities = ids[list], identities.indices.contains(index) else { return }
        identities.remove(at: index)
        ids[list] = identities
    }

    /// Follows a source through a rename, so its rows keep the identities the
    /// live text fields are holding.
    public mutating func renameSource(_ old: String, to new: String) {
        for (list, identities) in ids where list.source == old {
            ids[List(source: new, field: list.field)] = identities
            ids[list] = nil
        }
    }

    /// Drops a deleted source's lists.
    public mutating func removeSource(_ source: String) {
        for list in ids.keys where list.source == source {
            ids[list] = nil
        }
    }

    public mutating func removeAll() {
        ids = [:]
    }
}
