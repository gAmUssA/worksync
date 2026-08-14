import Foundation

/// The CLI exit-code contract (SPEC §8). Lives in the core so the mapping is a
/// pure function that unit tests can cover without spawning a process.
public enum ExitCodes {
    public static let success: Int32 = 0
    public static let configError: Int32 = 1
    public static let permissionError: Int32 = 2
    public static let partialFailure: Int32 = 3

    /// Maps any error a pass can surface to its documented exit code.
    ///
    /// Anything unrecognized maps to `partialFailure` rather than
    /// `configError`: an unexpected runtime failure is safe to re-run, whereas
    /// reporting it as a config error would send the user to edit a file that
    /// is not the problem.
    public static func code(for error: Error) -> Int32 {
        switch error {
        case is ConfigError, is ResolutionError:
            configError
        case let storeError as CalendarStoreError:
            switch storeError {
            case .accessDenied, .accessRestricted:
                permissionError
            case .backendError:
                partialFailure
            }
        default:
            partialFailure
        }
    }
}
