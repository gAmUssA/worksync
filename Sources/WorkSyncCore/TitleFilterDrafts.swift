import Foundation

/// Text typed into a source's title-filter add fields, remembered together with
/// the source it was typed for.
///
/// Ownership is part of the value rather than something every caller has to
/// remember to reset. A draft is readable only while its own source is
/// selected, so a missed "clear on selection change" can cost the user their
/// typing — it can never put a filter on a source they were not looking at.
///
/// The owner is a `SourceHandle`, not a config id. An id is editable data: a
/// late callback from a field built before a rename would otherwise re-own the
/// draft under the OLD id, and the source the user is looking at would read an
/// empty field and lose what they typed.
///
/// That is the failure this shape exists to make impossible. Clearing used to
/// live in one function the view called when the selection changed, but adding
/// and removing a source moved the selection themselves and left the id draft
/// already pointing at the new row, so the view's change handler saw nothing to
/// do and skipped the clear. The half-typed entry stayed in the field, and the
/// save committed it to whichever source was selected by then.
///
/// Kept here rather than in the menu bar target so the rule can be tested: the
/// app target has no test harness, and this is the part with a rule in it.
public struct TitleFilterDrafts: Equatable {
    /// The source every draft below belongs to.
    private var owner: SourceHandle?
    /// Draft text by field key. The keys are the caller's — this type does not
    /// need to know which fields exist.
    private var texts: [String: String]

    public init() {
        owner = nil
        texts = [:]
    }

    /// What `field` shows while `source` is selected. Empty for anyone else,
    /// including when nothing is selected.
    public func text(_ field: String, of source: SourceHandle?) -> String {
        guard let source, owner == source else { return "" }
        return texts[field] ?? ""
    }

    /// Records typing. Text entered for a different source than the one that
    /// owns the current drafts retires them — the user has moved on.
    public mutating func setText(_ text: String, _ field: String, of source: SourceHandle?) {
        guard let source else { return }
        if owner != source {
            owner = source
            texts = [:]
        }
        texts[field] = text
    }

    /// Records typing for a source that still exists.
    ///
    /// A field built before its source was removed carries a handle nothing
    /// answers to any more; taking its text would make a dead source the owner
    /// and hide the live source's draft behind it. Ignored instead.
    public mutating func setText(
        _ text: String, _ field: String, of handle: SourceHandle, in handles: SourceHandles
    ) {
        guard handles.id(of: handle) != nil else { return }
        setText(text, field, of: handle)
    }

    /// Empties one field, after its entry has been added to the list.
    public mutating func clear(_ field: String, of source: SourceHandle?) {
        guard let source, owner == source else { return }
        texts[field] = ""
    }

    /// Drops everything — the form is closing, or a fresh one is opening.
    public mutating func removeAll() {
        owner = nil
        texts = [:]
    }
}
