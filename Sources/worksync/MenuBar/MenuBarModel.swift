import AppKit
import Foundation
import Observation
import ServiceManagement
import WorkSyncCore
import WorkSyncKit

/// Icon state, driven by the last pass rather than by whoever last touched it.
enum SyncState: Equatable {
    case idle
    case syncing
    case error
    case paused

    var symbolName: String {
        switch self {
        case .idle: "calendar"
        case .syncing: "calendar.badge.clock"
        case .error: "calendar.badge.exclamationmark"
        case .paused: "calendar.badge.minus"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .idle: "WorkSync: idle"
        case .syncing: "WorkSync: syncing"
        case .error: "WorkSync: last sync failed"
        case .paused: "WorkSync: paused"
        }
    }
}

/// Shared state between the AppKit status item and the SwiftUI panel.
@MainActor
@Observable
final class MenuBarModel {
    private(set) var state: SyncState = .idle
    private(set) var isSyncing = false
    private(set) var lastRun: LastRun?
    private(set) var sourceCounts: [String: Int] = [:]
    private(set) var configError: String?

    /// Refreshed on every panel open and after every toggle, never trusted
    /// across those boundaries: the user can remove the login item in System
    /// Settings at any time, and a remembered value would report a lie
    /// (SPEC §10).
    private(set) var loginItemStatus: SMAppService.Status = .notRegistered

    var screen: PanelScreen = .dashboard
    var editingConfig: Config?
    var selectedSourceID: String?
    private(set) var availableCalendars: [CalendarRef] = []
    private(set) var settingsBlocked: String?
    var saveError: String?
    /// Set when a save succeeded but could not preserve the file's comments,
    /// so that loss is visible rather than inferred from a diff much later.
    var saveWarning: String?
    var pendingRename: PendingRename?
    /// The id field's text while it is being edited, held apart from
    /// `editingConfig` so a rename is judged once on commit rather than on
    /// every keystroke.
    var sourceIDDraft: SourceIDDraft?
    /// Why the typed id was refused, shown under the field.
    var renameError: String?
    /// Ids that exist in the saved file, so a rename of a brand-new source
    /// does not warn about orphaning events that cannot exist yet.
    var savedSourceIDs: Set<String> = []

    var isPaused: Bool {
        didSet {
            UserDefaults.standard.set(isPaused, forKey: Self.pausedKey)
            refreshState()
        }
    }

    /// A pass requested while one is in flight is remembered, not dropped
    /// (SPEC §11): losing a "Sync now" click is exactly the kind of silent
    /// no-op this design keeps guarding against.
    private var pendingRequest = false

    private let configPath: String
    private let logger: Logger

    static let pausedKey = "io.gamov.worksync.paused"

    init(configPath: String = ConfigLoader.defaultPath) {
        self.configPath = configPath
        isPaused = UserDefaults.standard.bool(forKey: Self.pausedKey)
        let level = (try? ConfigLoader.load(path: configPath).general.logLevel) ?? .info
        logger = Logger(level: level)
        lastRun = LastRunStore.load(path: LastRunStore.path(forConfigAt: configPath))
        savedSourceIDs = Set(((try? ConfigLoader.load(path: configPath))?.sources ?? []).map(\.id))
        refreshLoginItemStatus()
        refreshState()
    }

    // MARK: Launch at login

    func refreshLoginItemStatus() {
        loginItemStatus = LoginItem.status
    }

    var loginItemDescription: String {
        LoginItem.describe(loginItemStatus)
    }

    var launchesAtLogin: Bool {
        loginItemStatus == .enabled || loginItemStatus == .requiresApproval
    }

    /// Returns a message when the user has something to do, nil when the
    /// toggle simply took effect.
    @discardableResult
    func toggleLaunchAtLogin() -> String? {
        do {
            if launchesAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            refreshLoginItemStatus()
            return "Could not change launch at login: \(error.localizedDescription)"
        }

        refreshLoginItemStatus()
        if loginItemStatus == .requiresApproval {
            // Normal first-run behavior, not a failure (SPEC §10).
            SMAppService.openSystemSettingsLoginItems()
            return "Approve WorkSync in System Settings > General > Login Items."
        }
        return nil
    }

    var intervalMinutes: Int {
        (try? ConfigLoader.load(path: configPath).general.intervalMinutes) ?? 10
    }

    var headerLine: String {
        if let configError {
            return "Config error: \(configError)"
        }
        guard let lastRun else { return "No sync has run yet" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let when = formatter.localizedString(for: lastRun.finishedAt, relativeTo: Date())
        return lastRun.succeeded
            ? "Synced \(when) · \(lastRun.summary)"
            : "Last sync failed \(when)"
    }

    // MARK: Passes

    func syncNow() {
        guard !isPaused else { return }
        guard !isSyncing else {
            pendingRequest = true
            return
        }

        isSyncing = true
        refreshState()

        Task { [configPath, logger] in
            // Off the main actor: EventKit work must not block the panel.
            let outcome = await Task.detached(priority: .userInitiated) {
                PassRunner.run(
                    configPath: configPath,
                    makeStore: { EventKitStore() },
                    logger: logger,
                    lastRunPath: LastRunStore.path(forConfigAt: configPath)
                )
            }.value

            self.finish(outcome)
        }
    }

    private func finish(_ outcome: PassOutcome) {
        isSyncing = false
        lastRun = LastRunStore.load(path: LastRunStore.path(forConfigAt: configPath))

        switch outcome.disposition {
        case .completed:
            configError = nil
        case .skippedLocked:
            break // not news; the other holder is doing this same work
        case let .failed(message):
            configError = message
        }

        refreshRunCounts(from: outcome)
        refreshState()

        if pendingRequest {
            pendingRequest = false
            syncNow()
        }
    }

    private func refreshRunCounts(from outcome: PassOutcome) {
        guard let diagnostics = outcome.diagnostics else { return }
        sourceCounts = diagnostics.fetchedBySource
    }

    private func refreshState() {
        if isPaused {
            state = .paused
        } else if isSyncing {
            state = .syncing
        } else if configError != nil || lastRun?.succeeded == false {
            // Sticky until a pass succeeds, so a failure at 03:00 is still
            // visible at 09:00 (SPEC §11).
            state = .error
        } else {
            state = .idle
        }
    }

    // MARK: Menu actions

    func openConfig() {
        NSWorkspace.shared.open(URL(fileURLWithPath: configPath))
        // Validate immediately rather than letting a bad edit fail invisibly at
        // the next scheduled pass (SPEC §11).
        do {
            _ = try ConfigLoader.load(path: configPath)
            configError = nil
        } catch {
            configError = error.localizedDescription
        }
        refreshState()
    }

    func openLog() {
        let path = (Logger.defaultDirectory as NSString).appendingPathComponent("worksync.log")
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

// MARK: - Settings screen

enum PanelScreen: Equatable {
    case dashboard
    case settings
}

extension MenuBarModel {
    /// Opens the settings screen with a working copy of the config.
    ///
    /// Refuses when the file does not parse: presenting a form full of
    /// defaults would let a save overwrite a broken-but-recoverable file with
    /// something quite different from what the user wrote (SPEC §11.1).
    func openSettings() {
        do {
            editingConfig = try ConfigLoader.load(path: configPath)
            configError = nil
        } catch {
            editingConfig = nil
            configError = error.localizedDescription
            settingsBlocked = "config.toml does not parse, so settings cannot be edited safely.\n\n"
                + error.localizedDescription
                + "\n\nUse “Open config” to fix it by hand."
            return
        }
        settingsBlocked = nil
        loadCalendarChoices()
        selectedSourceID = editingConfig?.sources.first?.id
        sourceIDDraft = selectedSourceID.map(SourceIDDraft.init(id:))
        renameError = nil
        saveError = nil
        saveWarning = nil
        screen = .settings
    }

    func closeSettings() {
        screen = .dashboard
        editingConfig = nil
        pendingRename = nil
        sourceIDDraft = nil
        renameError = nil
    }

    /// Account/calendar choices for the popups, from the same enumeration
    /// `worksync calendars` uses. A popup cannot be typed wrong, and a free-text
    /// typo here hard-errors the whole sync (SPEC §11.1).
    private func loadCalendarChoices() {
        Task { [weak self] in
            let calendars = await Task.detached { () -> [CalendarRef] in
                let store = EventKitStore()
                guard (try? store.requestAccess()) != nil else { return [] }
                return (try? store.calendars()) ?? []
            }.value
            self?.availableCalendars = calendars
        }
    }

    var accountChoices: [String] {
        var seen = Set<String>()
        return availableCalendars.map(\.accountTitle).filter { seen.insert($0).inserted }.sorted()
    }

    func calendarChoices(inAccount account: String) -> [String] {
        availableCalendars
            .filter { $0.accountTitle.caseInsensitiveCompare(account) == .orderedSame }
            .map(\.title)
            .sorted()
    }

    func writableCalendarChoices(inAccount account: String) -> [String] {
        availableCalendars
            .filter { $0.accountTitle.caseInsensitiveCompare(account) == .orderedSame && $0.allowsModifications }
            .map(\.title)
            .sorted()
    }

    // MARK: Source list

    func addSource() {
        // Before reading editingConfig: an uncommitted rename has to land (or
        // be refused) while the list still looks the way the user left it.
        if sourceIDDraft?.isDirty == true {
            commitSourceIDDraft()
        }
        guard var config = editingConfig else { return }
        let base = "source"
        var name = base
        var counter = 2
        while config.sources.contains(where: { $0.id == name }) {
            name = "\(base)-\(counter)"
            counter += 1
        }
        let account = accountChoices.first ?? ""
        let calendar = calendarChoices(inAccount: account).first ?? ""
        config.sources.append(SourceConfig(id: name, account: account, calendar: calendar))
        editingConfig = config
        selectedSourceID = name
        sourceIDDraft = SourceIDDraft(id: name)
        renameError = nil
    }

    func removeSelectedSource() {
        guard var config = editingConfig, let selected = selectedSourceID else { return }
        guard let index = config.sources.firstIndex(where: { $0.id == selected }) else { return }
        config.sources.remove(at: index)
        editingConfig = config
        selectedSourceID = config.sources.first?.id
        // Deliberately not committed first: the draft belongs to the row being
        // deleted, so applying it would rename a source on its way out.
        sourceIDDraft = selectedSourceID.map(SourceIDDraft.init(id:))
        renameError = nil
        pendingRename = nil
    }

    func moveSources(from offsets: IndexSet, to destination: Int) {
        guard var config = editingConfig else { return }
        config.sources.move(fromOffsets: offsets, toOffset: destination)
        editingConfig = config
    }

    // MARK: Renaming a source

    /// Points the draft at `sourceID`, committing whatever was being typed
    /// first.
    ///
    /// Called when the selection changes, so switching rows cannot quietly
    /// discard a half-typed name — and cannot carry it over to the row the user
    /// just clicked either, since the draft resolves against its own
    /// `committedID` rather than against the selection.
    func seedSourceIDDraft(for sourceID: String?) {
        if sourceIDDraft?.isDirty == true {
            commitSourceIDDraft()
        }
        renameError = nil
        sourceIDDraft = sourceID.map(SourceIDDraft.init(id:))
    }

    /// Judges the accumulated draft text once, on commit — Enter, leaving the
    /// field, switching rows, or saving.
    ///
    /// Never on a keystroke: doing that made the first differing character
    /// count as a rename, so the warning opened mid-word and confirming it
    /// committed a partial id, orphaning every event under the real one.
    func commitSourceIDDraft() {
        guard let draft = sourceIDDraft, let config = editingConfig else { return }
        guard let index = config.sources.firstIndex(where: { $0.id == draft.committedID }) else { return }
        let others = config.sources.enumerated()
            .filter { $0.offset != index }
            .map(\.element.id)

        switch draft.commit(savedSourceIDs: savedSourceIDs, otherSourceIDs: others) {
        case .unchanged:
            renameError = nil
            sourceIDDraft?.revert() // normalizes away stray whitespace
        case let .rejected(reason):
            renameError = reason
        case let .apply(newID):
            renameError = nil
            applyRename(at: index, to: newID)
        case let .confirm(from, to):
            renameError = nil
            pendingRename = PendingRename(index: index, from: from, to: to)
        }
    }

    func confirmPendingRename() {
        guard let rename = pendingRename else { return }
        applyRename(at: rename.index, to: rename.to)
        pendingRename = nil
    }

    /// Cancelling puts the field back to the id the config still holds, so it
    /// never shows a name that was not applied.
    func cancelPendingRename() {
        pendingRename = nil
        sourceIDDraft?.revert()
    }

    private func applyRename(at index: Int, to newID: String) {
        guard var config = editingConfig, config.sources.indices.contains(index) else { return }
        config.sources[index].id = newID
        editingConfig = config
        selectedSourceID = newID
        sourceIDDraft?.markCommitted(newID)
    }

    // MARK: Saving

    /// Writes through the same writer everything else uses — comment
    /// preserving, self-checked, backed up. Never a UI-only write path.
    func saveSettings() {
        // Save is a commit point for the id field too. Without this, a name
        // typed but never submitted is silently dropped by the save it looks
        // like it was part of.
        if sourceIDDraft?.isDirty == true {
            commitSourceIDDraft()
        }
        // A refused id or an open warning has to be resolved first, otherwise
        // saving writes the old id while the field still shows the new one.
        guard renameError == nil, pendingRename == nil else { return }

        guard let config = editingConfig else { return }
        do {
            let outcome = try ConfigWriter.save(config, to: configPath)
            saveError = nil
            saveWarning = outcome.warning
            savedSourceIDs = Set(config.sources.map(\.id))
            configError = nil
            // Config is re-read at the start of every pass, so the change takes
            // effect on the next sync with no restart.
            closeSettings()
        } catch {
            saveError = error.localizedDescription
        }
        refreshState()
    }
}

struct PendingRename: Equatable {
    let index: Int
    let from: String
    let to: String
}
