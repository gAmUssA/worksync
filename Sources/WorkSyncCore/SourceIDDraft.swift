import Foundation

/// The text of a source-id field while the user is editing it, separate from
/// the id in the working config.
///
/// The separation is the whole point. Sending every keystroke straight at
/// `SourceRenamePolicy` means the first character that differs from a saved id
/// already counts as a rename: the confirmation alert opens mid-word, the field
/// snaps back to the old value because the config still holds it, and
/// confirming commits whatever partial string existed at that instant — which
/// orphans every event written under the real id. A draft accumulates freely
/// and is judged once, on commit.
public struct SourceIDDraft: Equatable {
    /// The id the working config currently holds for this source. Commits are
    /// resolved against this rather than against a selection, so a commit
    /// triggered by clicking a different row still targets the right source.
    public private(set) var committedID: String
    /// What is in the text field right now.
    public var text: String

    public init(id: String) {
        committedID = id
        text = id
    }

    public var isDirty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines) != committedID
    }

    /// Marks the draft as saved under `id`, so a second commit is a no-op
    /// rather than a second alert for the same rename.
    public mutating func markCommitted(_ id: String) {
        committedID = id
        text = id
    }

    /// Throws away the typed text. Used when the user cancels the warning.
    public mutating func revert() {
        text = committedID
    }

    /// What committing the current text should do.
    public enum Commit: Equatable {
        /// Nothing to apply — unchanged, or only whitespace differs.
        case unchanged
        /// Not a usable id. `reason` is user-facing.
        case rejected(reason: String)
        /// Valid, but the old id has events under it: ask first.
        case confirm(from: String, to: String)
        /// Valid and safe to apply immediately.
        case apply(String)
    }

    /// Judges the accumulated text once.
    ///
    /// - Parameters:
    ///   - savedSourceIDs: ids present in the config file on disk. Only those
    ///     can have events written under them, so only those need a warning.
    ///   - otherSourceIDs: every other source in the working config, so a
    ///     collision is caught here rather than at save time, where the error
    ///     names a file rather than the field that caused it.
    public func commit(savedSourceIDs: Set<String>, otherSourceIDs: [String]) -> Commit {
        let candidate: String
        do {
            // The same normalization the loader applies, so the editor cannot
            // produce an id the parser would refuse to read back.
            candidate = try ConfigLoader.normalizedSourceID(text)
        } catch {
            return .rejected(reason: (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription)
        }

        guard candidate != committedID else { return .unchanged }

        // Matches `ConfigLoader.validate`, which compares lowercased: two
        // sources differing only in case would collide on save.
        guard !otherSourceIDs.contains(where: { $0.lowercased() == candidate.lowercased() }) else {
            return .rejected(reason: "Another source is already called “\(candidate)”.")
        }

        guard SourceRenamePolicy.needsWarning(
            renaming: committedID, to: candidate, savedSourceIDs: savedSourceIDs
        ) else {
            return .apply(candidate)
        }
        return .confirm(from: committedID, to: candidate)
    }
}
