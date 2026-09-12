import Foundation

/// Which single message the settings footer shows.
///
/// Pure and AppKit-free so the precedence is a tested rule rather than the
/// order two `??` operands happen to be written in (SPEC §11.1).
public enum SettingsMessagePolicy {
    /// A live validation problem wins over a write error.
    ///
    /// The write error describes a save that already failed and cannot be
    /// retried until the form is valid again; the validation problem is why
    /// Save is disabled *now*. Showing the stale one leaves the user staring at
    /// a greyed-out button with an explanation that no longer applies to it.
    public static func footerMessage(validationProblem: String?, saveError: String?) -> String? {
        validationProblem ?? saveError
    }
}
