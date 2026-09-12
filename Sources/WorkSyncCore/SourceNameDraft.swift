import Foundation

/// The source-name field's text, together with the source it belongs to.
///
/// `SourceIDDraft` judges what was typed; this says whose typing it is. The name
/// field was the one per-source control still reading and writing the model's
/// draft directly, so a setter retained while one source was selected could put
/// its text into the next source's field — and committing then renamed the wrong
/// source, or staged the wrong source's orphan warning.
///
/// A callback that does not own the field is ignored. Storing an owner beside a
/// draft anyone can write does not protect it: the ownership check has to be on
/// the way in.
public struct SourceNameDraft: Equatable {
    private var owner: SourceHandle?
    private var draft: SourceIDDraft?

    public init() {}

    /// Points the field at a source, discarding whatever was typed for another.
    public mutating func seed(_ handle: SourceHandle?, id: String?) {
        owner = handle
        draft = id.map(SourceIDDraft.init(id:))
    }

    /// What the field shows for `handle`: its own text, or `fallback` — the
    /// source's current id — for any other source.
    public func text(of handle: SourceHandle?, fallback: String) -> String {
        guard let handle, owner == handle, let draft else { return fallback }
        return draft.text
    }

    /// Records typing. Ignored unless `handle` owns the field.
    public mutating func setText(_ text: String, of handle: SourceHandle?) {
        guard let handle, owner == handle else { return }
        draft?.text = text
    }

    /// The draft `handle` owns, for a commit that came from that source's own
    /// control. Nil for any other source.
    public func draft(of handle: SourceHandle?) -> SourceIDDraft? {
        guard let handle, owner == handle else { return nil }
        return draft
    }

    /// The field's owner and its draft, for the form's own commit points —
    /// saving, switching rows, adding a source — which act on whatever is being
    /// edited rather than on a source a callback named.
    public var pending: (handle: SourceHandle, draft: SourceIDDraft)? {
        guard let owner, let draft else { return nil }
        return (owner, draft)
    }

    public var isDirty: Bool {
        draft?.isDirty ?? false
    }

    /// Throws away the typed text, back to the id the config still holds.
    public mutating func revert() {
        draft?.revert()
    }

    /// Marks the field saved under `id`, so a second commit is a no-op rather
    /// than a second alert for the same rename.
    public mutating func markCommitted(_ id: String) {
        draft?.markCommitted(id)
    }

    public mutating func removeAll() {
        owner = nil
        draft = nil
    }
}
