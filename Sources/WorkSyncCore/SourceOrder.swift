import Foundation

/// Reordering the source list.
///
/// Order is load-bearing rather than cosmetic — the first-listed source wins
/// cross-source dedup (SPEC §5 step 5) — so a drop is either applied exactly as
/// the user drew it or not at all. Reordering the wrong source silently changes
/// which source supplies a shared event's blocker.
///
/// A drag is the one callback in this form that cannot be addressed by handle:
/// SwiftUI hands back offsets, which name positions in the list the drag was
/// computed against. So the snapshot itself is validated instead. In-range is
/// not the same as still-meaningful — drag `B` at offset 1 of `[A, B, C, D]` to
/// offset 3, lose `A` before the drop lands, and offsets `(1, 3)` still fit
/// `[B, C, D]` while naming `C`, which the user never touched.
///
/// Only the check lives here. The move itself stays where it was, so the
/// reorder keeps the framework's exact semantics rather than a reimplementation
/// of them.
public enum SourceOrder {
    /// Whether a drop computed against `rendered` still applies to `current`.
    ///
    /// - Parameters:
    ///   - rendered: the source identities the dragged rows were built from.
    ///   - current: the identities in the list the drop is about to be applied
    ///     to.
    public static func canMove(
        fromOffsets offsets: IndexSet,
        toOffset destination: Int,
        rendered: [SourceHandle],
        current: [SourceHandle]
    ) -> Bool {
        guard !offsets.isEmpty else { return false }
        // The list the offsets mean something in. Anything else — a source
        // added, removed, or already reordered since the drag started — and the
        // offsets name rows the user did not drag.
        guard rendered == current else { return false }
        // Kept from before: a malformed callback must not reach `move`, which
        // traps rather than tolerating an offset past the end.
        guard offsets.allSatisfy({ current.indices.contains($0) }) else { return false }
        return (0 ... current.count).contains(destination)
    }
}
