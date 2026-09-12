import Foundation

/// Text typed into each source's title-filter add fields.
///
/// **Every source gets its own storage.** A draft used to be a single owner plus
/// a guard — "whose text is this, and may that source still write?" — and that
/// shape kept producing the same bug in new disguises. The guard could only ask
/// whether a callback's source still existed, so two live sources defeated it: a
/// late setter from the source the user had just left took ownership, and the
/// text typed into the source they were looking at vanished.
///
/// Keyed by handle there is nothing to take. A late setter writes into its own
/// source's slot, which nobody is reading, and the selected source's text is
/// untouched by construction rather than by a check somebody has to remember.
///
/// **Reset policy.** Drafts are per source, but they do not outlive the user's
/// attention: moving the selection discards all of them (`removeAll`), which is
/// the behaviour the form has always had — a half-typed entry belongs to the
/// moment, and carrying it back would surprise a user who left it behind.
/// Removing a source drops its drafts with it, and closing the form drops
/// everything.
///
/// Kept here rather than in the menu bar target so the rule can be tested: the
/// app target has no test harness, and this is the part with a rule in it.
public struct TitleFilterDrafts: Equatable {
    /// Draft text by field key, per source. The field keys are the caller's —
    /// this type does not need to know which fields exist.
    private var texts: [SourceHandle: [String: String]] = [:]

    public init() {}

    /// What `field` shows for `source`. Empty for a source that has typed
    /// nothing, and for no source at all.
    public func text(_ field: String, of source: SourceHandle?) -> String {
        guard let source else { return "" }
        return texts[source]?[field] ?? ""
    }

    /// Records typing against the source it was typed into. No other source's
    /// text is reachable from here, whichever callback arrives.
    public mutating func setText(_ text: String, _ field: String, of source: SourceHandle?) {
        guard let source else { return }
        texts[source, default: [:]][field] = text
    }

    /// Records typing for a source that still exists.
    ///
    /// A field built before its source was removed carries a handle nothing
    /// answers to any more. Its text is dropped rather than stored against a
    /// dead source, where it would linger until the form closed.
    public mutating func setText(
        _ text: String, _ field: String, of handle: SourceHandle, in handles: SourceHandles
    ) {
        guard handles.id(of: handle) != nil else { return }
        setText(text, field, of: handle)
    }

    /// Empties one field, after its entry has been added to the list.
    public mutating func clear(_ field: String, of source: SourceHandle?) {
        guard let source else { return }
        texts[source]?[field] = ""
    }

    /// Drops a removed source's drafts. They die with the source rather than
    /// waiting for the next selection change to sweep them up.
    public mutating func remove(_ source: SourceHandle) {
        texts[source] = nil
    }

    /// Drops everything — the selection moved, or the form is closing.
    public mutating func removeAll() {
        texts = [:]
    }
}
