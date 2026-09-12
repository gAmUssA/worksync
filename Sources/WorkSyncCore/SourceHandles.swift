import Foundation

/// A source's identity for as long as the settings form is open.
///
/// The config id is not identity: it is editable data. The user can rename a
/// source, and a removed source's id can be taken by a new one. A callback that
/// carries only an id therefore names "whatever is called that *now*", which is
/// how a late edit from one source came to land on another.
///
/// Minted when the editing config loads, carried by the controls, and dead the
/// moment its source is removed.
public struct SourceHandle: Hashable, Sendable {
    private let value: UUID

    init(value: UUID = UUID()) {
        self.value = value
    }
}

/// The source an operation is acting on: its editing identity and the id that
/// identity currently names.
///
/// One value, produced by resolving a handle, so the two halves cannot
/// disagree — the failure that had a commit add to one source's list while
/// clearing another's draft.
public struct EditedSource: Equatable {
    public let handle: SourceHandle
    public let id: String

    public init(handle: SourceHandle, id: String) {
        self.handle = handle
        self.id = id
    }
}

/// Which source each editing identity currently names.
///
/// Rename moves the id under a handle; the handle does not change, so nothing
/// keyed by it has to be re-keyed. Removal retires the handle, and every
/// callback still holding it resolves to nothing from then on — ignored, never
/// retargeted at whatever now answers to that id.
public struct SourceHandles: Equatable {
    private var ids: [SourceHandle: String] = [:]

    public init() {}

    /// Fresh identities for a freshly loaded config. Everything minted before
    /// is retired: those handles belong to an editing session that has ended.
    public mutating func seed(_ sourceIDs: [String]) {
        ids = [:]
        for id in sourceIDs {
            ids[SourceHandle()] = id
        }
    }

    /// An identity for a source that did not exist when the form opened.
    public mutating func mint(_ id: String) -> SourceHandle {
        let handle = SourceHandle()
        ids[handle] = id
        return handle
    }

    /// The id `handle` names, or nil once its source is gone.
    public func id(of handle: SourceHandle) -> String? {
        ids[handle]
    }

    /// `handle` paired with the id it names, or nil once its source is gone.
    public func resolve(_ handle: SourceHandle?) -> EditedSource? {
        guard let handle, let id = ids[handle] else { return nil }
        return EditedSource(handle: handle, id: id)
    }

    /// The identity currently naming `id`, for a list that still speaks ids.
    public func handle(of id: String) -> SourceHandle? {
        ids.first { $0.value == id }?.key
    }

    /// Follows a rename. The handle is unchanged, which is the point: nothing
    /// keyed by it needs to know a rename happened.
    public mutating func rename(_ handle: SourceHandle, to id: String) {
        guard ids[handle] != nil else { return }
        ids[handle] = id
    }

    /// Retires an identity. Callbacks still holding it resolve to nothing.
    public mutating func remove(_ handle: SourceHandle) {
        ids[handle] = nil
    }

    public mutating func removeAll() {
        ids = [:]
    }
}
