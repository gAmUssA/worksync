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

/// What happened when the name field was committed.
///
/// Returned rather than signalled by setting `renameError` and hoping the caller
/// looks: a commit that refuses the typed name has to stop whatever was about to
/// happen, and a caller cannot stop for a side effect it never reads. Adding a
/// source used to commit, ignore the refusal, and carry on; switching rows used
/// to commit, ignore the refusal, and then clear both the typed name and the
/// error on its way past.
public enum SourceNameCommit: Equatable {
    /// Nothing was being edited, or the text resolved to the id it already had.
    case settled
    /// Applied — the source now answers to `id`.
    case renamed(String)
    /// The rename orphans events, so the user has to confirm it first.
    case awaitingConfirmation
    /// Refused. The typed text is still in the field and `reason` is under it.
    case rejected(reason: String)

    /// Whether the action that triggered this commit must stop.
    ///
    /// A refusal has to stop it, and so does an open confirmation: the alert
    /// names one source, and whatever comes next would happen behind it.
    public var blocksAction: Bool {
        switch self {
        case .settled, .renamed: false
        case .awaitingConfirmation, .rejected: true
        }
    }
}
