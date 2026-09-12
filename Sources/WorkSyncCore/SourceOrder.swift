import Foundation

/// Reordering the source list.
///
/// Order is load-bearing rather than cosmetic — the first-listed source wins
/// cross-source dedup (SPEC §4.1) — so a drop is either applied exactly or not
/// at all.
///
/// A drag hands back offsets into the list as the drop saw it. Applying those to
/// a list that has since lost a source does not reorder it wrongly, it traps:
/// `move(fromOffsets:toOffset:)` has no tolerance for an offset past the end.
/// The same shape as the stale row and source indices before it.
///
/// Only the check lives here. The move itself stays where it was, so the
/// reorder keeps the framework's exact semantics rather than a reimplementation
/// of them.
public enum SourceOrder {
    /// Whether this move fits `sources`.
    ///
    /// The destination may equal `count` — that is "past the last row", which is
    /// how a drop below everything arrives.
    public static func canMove(
        _ sources: [SourceConfig], fromOffsets offsets: IndexSet, toOffset destination: Int
    ) -> Bool {
        guard !offsets.isEmpty else { return false }
        guard offsets.allSatisfy({ sources.indices.contains($0) }) else { return false }
        return (0 ... sources.count).contains(destination)
    }
}
