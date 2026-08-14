import Foundation

/// A whole pass — lock, plan, apply, record — behind one call, so the CLI and
/// the menu bar cannot drift apart (SPEC §3: no logic may live in only one
/// mode).
public struct PassOutcome: Sendable {
    public enum Disposition: Sendable, Equatable {
        case completed
        /// Another process held the lock. Normal, not a failure (SPEC §9).
        case skippedLocked
        case failed(String)
    }

    public let disposition: Disposition
    public let result: ApplyResult?
    public let diagnostics: PassDiagnostics?

    public var summary: String {
        switch disposition {
        case .completed:
            result?.summaryLine ?? "no changes"
        case .skippedLocked:
            "another sync is already running"
        case let .failed(message):
            message
        }
    }

    public var succeeded: Bool {
        if case .completed = disposition {
            return result?.hasFailures != true
        }
        return false
    }
}

public enum PassRunner {
    /// Runs one full pass. Never throws: the menu bar has nowhere to throw to,
    /// and a failed pass must leave the app running and reportable.
    public static func run(
        configPath: String = ConfigLoader.defaultPath,
        makeStore: () -> CalendarStore,
        now: Date = Date(),
        logger: Logger? = nil,
        lockPath: String = RunLock.defaultPath,
        recordLastRun: Bool = true,
        lastRunPath: String = LastRunStore.defaultPath
    ) -> PassOutcome {
        let config: Config
        do {
            config = try ConfigLoader.load(path: configPath)
        } catch {
            return finish(.failed(error.localizedDescription), nil, nil, logger, recordLastRun, lastRunPath, now)
        }

        let lock: RunLock?
        do {
            guard let acquired = try RunLock.acquire(path: lockPath) else {
                // Deliberately not recorded as a run: nothing happened, and
                // overwriting a good last-run record with "skipped" would make
                // the menu bar header useless.
                logger?.debug("pass skipped: another process holds the lock")
                return PassOutcome(disposition: .skippedLocked, result: nil, diagnostics: nil)
            }
            lock = acquired
        } catch {
            return finish(.failed(error.localizedDescription), nil, nil, logger, recordLastRun, lastRunPath, now)
        }
        defer { lock?.unlock() }

        let store = makeStore()
        do {
            try store.requestAccess()
        } catch {
            return finish(.failed(error.localizedDescription), nil, nil, logger, recordLastRun, lastRunPath, now)
        }

        let pass: PlannedPass
        do {
            pass = try SyncPipeline.plan(config: config, store: store, now: now)
        } catch {
            return finish(.failed(error.localizedDescription), nil, nil, logger, recordLastRun, lastRunPath, now)
        }

        for (sourceID, count) in pass.diagnostics.unidentifiableBySource {
            logger?.warn("source \(sourceID): skipped \(count) event(s) with no stable identifier")
        }

        let result = SyncEngine.apply(pass.plan, store: store)
        for failure in result.failures {
            logger?.error(failure)
        }

        return finish(.completed, result, pass.diagnostics, logger, recordLastRun, lastRunPath, now)
    }

    private static func finish(
        _ disposition: PassOutcome.Disposition,
        _ result: ApplyResult?,
        _ diagnostics: PassDiagnostics?,
        _ logger: Logger?,
        _ recordLastRun: Bool,
        _ lastRunPath: String,
        _ now: Date
    ) -> PassOutcome {
        let outcome = PassOutcome(disposition: disposition, result: result, diagnostics: diagnostics)

        if case let .failed(message) = disposition {
            logger?.error(message)
        } else {
            logger?.info(outcome.summary)
        }

        if recordLastRun {
            LastRunStore.save(LastRun(
                finishedAt: now,
                succeeded: outcome.succeeded,
                summary: outcome.summary,
                errorMessage: outcome.succeeded ? result?.failures.first : outcome.summary
            ), path: lastRunPath)
        }
        return outcome
    }
}
