import Foundation

/// Whether renaming a source id needs to warn the user first.
///
/// Pure and tested rather than inline in the settings screen: getting this
/// wrong is silently destructive in one direction (renaming a live source
/// orphans every event already written under the old id, reachable afterwards
/// only through `purge --source`) and merely annoying in the other (warning
/// about a source that has never been saved, so nothing can exist under it).
public enum SourceRenamePolicy {
    public static func needsWarning(
        renaming oldID: String,
        to newID: String,
        savedSourceIDs: Set<String>
    ) -> Bool {
        guard oldID != newID else { return false }
        // A source that was never saved has no events to orphan.
        return savedSourceIDs.contains(oldID)
    }

    /// The recovery command to show alongside the warning.
    public static func recoveryCommand(forOrphansOf oldID: String) -> String {
        "worksync purge --source \(oldID)"
    }
}
