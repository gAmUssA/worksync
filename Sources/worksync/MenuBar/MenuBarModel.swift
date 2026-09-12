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
    /// The last doctor run, or nil before the first one. Drives the icon as
    /// well as the panel: a problem the user has not opened the panel to see
    /// is exactly the one worth showing in the menu bar.
    private(set) var health: DoctorReport?
    private(set) var isCheckingHealth = false

    /// Refreshed on every panel open and after every toggle, never trusted
    /// across those boundaries: the user can remove the login item in System
    /// Settings at any time, and a remembered value would report a lie
    /// (SPEC §10).
    private(set) var loginItemStatus: SMAppService.Status = .notRegistered

    var screen: PanelScreen = .dashboard
    var editingConfig: Config?
    /// Current ID -> ID on disk when settings opened. New sources have no entry.
    private var sourceOrigins: [String: String] = [:]
    /// The selected source's editing identity. The config id is data the user
    /// can edit; this is what the form's controls carry and resolve.
    var selectedSource: SourceHandle?
    /// Which identity names which source right now.
    private var sourceHandles = SourceHandles()
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
    /// The name field's text and the source it belongs to. A callback that does
    /// not own the field cannot write to it.
    private(set) var sourceNameDraft = SourceNameDraft()
    /// Why the typed id was refused, shown under the field.
    var renameError: String?
    /// Ids that exist in the saved file, so a rename of a brand-new source
    /// does not warn about orphaning events that cannot exist yet.
    var savedSourceIDs: Set<String> = []
    /// What is typed into each title-filter list's "add" field. The value
    /// remembers which source it was typed for, so a half-typed entry cannot
    /// follow the user to a different one even if a path forgets to clear it.
    var titleFilterDrafts = TitleFilterDrafts()
    /// Identities for the rows on screen, so an edit lands on the row it was
    /// typed into rather than on whatever has shifted into its position.
    private var titleFilterRowIDs = TitleFilterRowIDs()

    /// Backing storage so the initializer can set it without the observer
    /// running before `services` exists.
    private var isPausedStorage: Bool
    var isPaused: Bool {
        get { isPausedStorage }
        set {
            isPausedStorage = newValue
            services.writePaused(newValue)
            refreshState()
        }
    }

    /// A pass requested while one is in flight is remembered, not dropped
    /// (SPEC §11): losing a "Sync now" click is exactly the kind of silent
    /// no-op this design keeps guarding against.
    private var pendingRequest = false

    /// Every effect this model has on the world outside itself. The only way
    /// it reaches a file, a default, the calendar store or the clock.
    private let services: MenuBarServices

    /// Change-driven state. All main-actor confined.
    private var changeObserver: CalendarChangeObserver?
    private var changePolicy: ChangeTriggerPolicy?
    private var changeTimer: MenuBarScheduledAction?
    /// When a pass last actually wrote something, for echo suppression.
    private var lastWriteAt: Date?
    /// Gates *starting* observation: a successful pass proves calendar access.
    private var hasCompletedAPass = false

    static let pausedKey = "io.gamov.worksync.paused"

    /// Handles for the work this model starts, so a test can await the actual
    /// completion — including the model applying the result — rather than
    /// guessing when a fake was called.
    @ObservationIgnored var healthTask: Task<Void, Never>?
    @ObservationIgnored var calendarChoicesTask: Task<Void, Never>?
    @ObservationIgnored var passTask: Task<Void, Never>?

    /// The only designated initializer, and it is inert: it assigns the state
    /// it is given and computes what is pure. It calls no service.
    ///
    /// That is the whole seam. Construction used to read UserDefaults, load the
    /// config and last-run files, create the log directory, ask SMAppService for
    /// a status and start gathering health — so no test could build one without
    /// touching the machine, and the editing logic that produced eleven rounds
    /// of fixes was tested through a hand-written copy instead.
    init(initialState: MenuBarInitialState, services: MenuBarServices) {
        self.services = services
        isPausedStorage = initialState.isPaused
        lastRun = initialState.lastRun
        savedSourceIDs = initialState.savedSourceIDs
        refreshState() // pure: derives the icon from state already assigned
    }

    /// What the initializer used to do at the end of itself.
    ///
    /// Production calls this from `live(configPath:)`, at the same point in the
    /// lifecycle as before. A test calls the same method on an inert model with
    /// fake services, so startup is exercised rather than skipped.
    func startInitialRefreshes() {
        refreshLoginItemStatus()
        // At launch, so the icon tells the truth before the panel is ever
        // opened — the whole point of surfacing health in the menu bar.
        refreshHealth()
    }

    // MARK: Launch at login

    func refreshLoginItemStatus() {
        loginItemStatus = services.loginItemStatus()
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
                try services.unregisterLoginItem()
            } else {
                try services.registerLoginItem()
            }
        } catch {
            refreshLoginItemStatus()
            return "Could not change launch at login: \(error.localizedDescription)"
        }

        refreshLoginItemStatus()
        if loginItemStatus == .requiresApproval {
            // Normal first-run behavior, not a failure (SPEC §10).
            services.openLoginItemSettings()
            return "Approve WorkSync in System Settings > General > Login Items."
        }
        return nil
    }

    var intervalMinutes: Int {
        (try? services.loadConfig().general.intervalMinutes) ?? 10
    }

    var headerLine: String {
        if let configError {
            return "Config error: \(configError)"
        }
        guard let lastRun else { return "No sync has run yet" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let when = formatter.localizedString(for: lastRun.finishedAt, relativeTo: services.now())
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

        passTask = Task { [services] in
            let outcome = await services.runPass()
            self.finish(outcome)
        }
    }

    private func finish(_ outcome: PassOutcome) {
        isSyncing = false
        lastRun = services.loadLastRun()

        switch outcome.disposition {
        case .completed:
            configError = nil
            // Stamped before anything else can observe the change, so the
            // echo window is measured from the write rather than from
            // whenever this method happens to finish.
            if outcome.result?.wroteAnything == true {
                lastWriteAt = services.now()
            }
            // Only now: a successful pass is proof access is granted, which is
            // what makes starting the observer meaningful (SPEC §11.2).
            hasCompletedAPass = true
            reconcileChangeObservation()
        case .skippedLocked:
            break // not news; the other holder is doing this same work
        case let .failed(message):
            configError = message
        }

        refreshRunCounts(from: outcome)
        refreshState()
        // A pass is when the environment most plausibly changed — access
        // revoked, a calendar renamed, the target made read-only.
        refreshHealth()
        notify(about: outcome)

        if pendingRequest {
            pendingRequest = false
            syncNow()
        }
    }

    // MARK: Change-driven fast path

    /// Starts observing calendar changes, if the config asks for it.
    ///
    /// Called only after a successful pass, so access is known-granted rather
    /// than assumed — starting earlier would register an observer that can
    /// never fire and report itself as working (SPEC §11.2).
    /// Brings observation in line with the config as it is right now.
    ///
    /// Called after every pass and after every settings save, because both
    /// `change_driven` and `change_debounce_seconds` are editable while the app
    /// is running. Reconciling rather than starting once is what makes turning
    /// the feature off actually turn it off.
    func reconcileChangeObservation() {
        guard let config = try? services.loadConfig() else { return }

        switch ChangeObservationPlan.reconcile(
            config: config,
            observing: changeObserver != nil,
            currentPolicy: changePolicy,
            hasCompletedAPass: hasCompletedAPass
        ) {
        case .doNothing:
            break

        case let .start(policy):
            changePolicy = policy
            let observer = services.makeChangeObserver()
            changeObserver = observer
            observer.start { [weak self] in
                // Notifications arrive on an arbitrary queue; everything below
                // touches main-actor state (SPEC §3.1 rule 4).
                Task { @MainActor [weak self] in
                    self?.calendarDidChange()
                }
            }
            services.log(.info, "change-driven sync enabled (debounce \(policy.debounceSeconds)s)")

        case let .updatePolicy(policy):
            changePolicy = policy
            // A timer already armed under the old debounce would otherwise
            // fire at the old interval once more.
            changeTimer?.cancel()
            changeTimer = nil
            services.log(.info, "change-driven debounce now \(policy.debounceSeconds)s")

        case .stop:
            changeObserver?.stop()
            changeObserver = nil
            changePolicy = nil
            // Without this, a pass already scheduled before the user turned
            // the feature off still fires afterwards — the one sync they
            // explicitly asked not to happen.
            changeTimer?.cancel()
            changeTimer = nil
            services.log(.info, "change-driven sync disabled")
        }
    }

    private func calendarDidChange() {
        guard let policy = changePolicy, !isPaused else { return }

        switch policy.action(now: services.now(), lastWriteAt: lastWriteAt) {
        case .ignoreEcho:
            // Our own commit coming back. Without this, every writing pass
            // schedules exactly one no-op pass behind it, forever.
            services.log(.debug, "calendar change ignored: own write echo")
        case let .armTimer(delay):
            // Re-arms the single timer rather than adding another, so a burst
            // of notifications for one user edit collapses into one pass.
            changeTimer?.cancel()
            changeTimer = services.scheduleChange(delay) { [weak self] in
                self?.services.log(.debug, "change-driven pass firing")
                self?.syncNow()
            }
        }
    }

    /// Notifications are menu bar only (SPEC §4.1): the headless launchd path
    /// has no session to post into, and `worksync sync` in a terminal already
    /// prints its summary.
    private func notify(about outcome: PassOutcome) {
        // Re-read rather than cached, so switching notify in the settings
        // screen takes effect on the next pass instead of the next launch —
        // matching how every other setting behaves.
        let mode = (try? services.loadConfig().general.notify) ?? .off
        guard let notification = NotificationPolicy.notification(for: outcome, mode: mode) else { return }
        services.notifier.post(notification)
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
        } else if configError != nil || lastRun?.succeeded == false || health?.worstSeverity == .error {
            // Health counts, not just the last pass. Revoked calendar access
            // makes every pass succeed at doing nothing, so a sync-only icon
            // stays green while the tool is completely broken (SPEC §16) —
            // the one failure the user most needs to see without opening
            // anything.
            //
            // Sticky until a pass succeeds, so a failure at 03:00 is still
            // visible at 09:00 (SPEC §11).
            state = .error
        } else {
            state = .idle
        }
    }

    // MARK: Health

    /// Runs the same checks `worksync doctor` runs — the CLI computes, the UI
    /// renders. A second implementation here would drift, and the first time
    /// the two disagreed the user would trust neither.
    func refreshHealth() {
        guard !isCheckingHealth else { return }
        isCheckingHealth = true
        healthTask = Task { [services] in
            let report = await services.healthReport()
            self.health = report
            self.isCheckingHealth = false
            self.refreshState()
        }
    }

    /// Errors first, then warnings — what to fix, in the order to fix it.
    /// Passing and skipped checks are left out: the panel answers "is anything
    /// wrong", and `worksync doctor` is where the full list lives.
    var healthProblems: [DoctorFinding] {
        guard let health else { return [] }
        return health.findings
            .filter { $0.severity == .error || $0.severity == .warning }
            .sorted { $0.severity > $1.severity }
    }

    var healthSummary: String {
        guard let health else { return isCheckingHealth ? "Checking…" : "Not checked yet" }
        return health.summaryLine
    }

    /// Sends the user where the fix actually is.
    func open(_ destination: DoctorDestination) {
        switch destination {
        case .configFile:
            openConfig()
        case .loginItemSettings:
            services.openLoginItemSettings()
        case .calendarPrivacySettings:
            openSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        case .notificationSettings:
            openSettingsPane("x-apple.systempreferences:com.apple.preference.notifications")
        }
    }

    private func openSettingsPane(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        services.openURL(url)
    }

    // MARK: Menu actions

    func openConfig() {
        services.openURL(services.configURL())
        // Validate immediately rather than letting a bad edit fail invisibly at
        // the next scheduled pass (SPEC §11).
        do {
            _ = try services.loadConfig()
            configError = nil
        } catch {
            configError = error.localizedDescription
        }
        refreshState()
    }

    func openLog() {
        services.openURL(services.logURL())
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
            let config = try services.loadConfig()
            editingConfig = config
            sourceHandles.seed(config.sources.map(\.id))
            sourceOrigins = Dictionary(uniqueKeysWithValues: config.sources.map { ($0.id, $0.id) })
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
        seedTitleFilterRowIDs()
        loadCalendarChoices()
        select(editingConfig?.sources.first.flatMap { sourceHandles.handle(of: $0.id) })
        saveError = nil
        saveWarning = nil
        screen = .settings
    }

    func closeSettings() {
        // The list belongs to the form that asked for it, so it dies with it.
        calendarChoicesTask?.cancel()
        screen = .dashboard
        editingConfig = nil
        sourceOrigins = [:]
        pendingRename = nil
        sourceNameDraft.removeAll()
        renameError = nil
        titleFilterDrafts.removeAll()
        titleFilterRowIDs.removeAll()
        sourceHandles.removeAll()
    }

    /// Account/calendar choices for the popups, from the same enumeration
    /// `worksync calendars` uses. A popup cannot be typed wrong, and a free-text
    /// typo here hard-errors the whole sync (SPEC §11.1).
    private func loadCalendarChoices() {
        // One lookup at a time, and only the current one may publish. Opening
        // settings again while an enumeration is still running would otherwise
        // let the old session finish last and repopulate the pickers with the
        // calendars it found — silently, and long after the list it belongs to
        // is gone.
        calendarChoicesTask?.cancel()
        calendarChoicesTask = Task { [services] in
            let calendars = await services.calendarChoices()
            guard !Task.isCancelled else { return }
            self.availableCalendars = calendars
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
        // be refused) while the list still looks the way the user left it. A
        // refusal stops the add, the way it stops a save — the user has a name
        // on screen that cannot be applied, and adding a source underneath it
        // would clear the error and move the selection off the problem.
        //
        // Asked unconditionally. Gating this on a dirty field inferred "nothing
        // is pending" from "nothing has been typed since", which an open alert
        // and a restored name together make false.
        if commitSourceIDDraft().blocksAction {
            return
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
        // The dirty id draft was already committed above, while the list still
        // looked the way the user left it.
        select(sourceHandles.mint(name))
    }

    func removeSelectedSource() {
        guard var config = editingConfig, let selected = sourceHandles.resolve(selectedSource) else { return }
        guard let index = config.sources.firstIndex(where: { $0.id == selected.id }) else { return }
        config.sources.remove(at: index)
        sourceOrigins.removeValue(forKey: selected.id)
        titleFilterRowIDs.removeSource(selected.handle)
        // Retires the identity: every control still holding it now resolves to
        // nothing, rather than to whichever source later takes that id.
        sourceHandles.remove(selected.handle)
        editingConfig = config
        // Deliberately not committing first: the draft belongs to the row being
        // deleted, so applying it would rename a source on its way out.
        select(config.sources.first.flatMap { sourceHandles.handle(of: $0.id) })
        pendingRename = nil
    }

    /// A drop carries offsets into the list as it looked when the drag started.
    /// Applying them to a list that has since changed traps, so a move that does
    /// not fit is ignored.
    /// A drop carries offsets into the list as it looked when the drag started,
    /// so `rendered` carries that list's identities with it. A drop against a
    /// list that has changed since is ignored: its offsets would still be in
    /// range and would name rows the user never dragged.
    func moveSources(from offsets: IndexSet, to destination: Int, rendered: [SourceHandle]) {
        guard var config = editingConfig,
              SourceOrder.canMove(
                  fromOffsets: offsets, toOffset: destination,
                  rendered: rendered, current: sourceRows.map(\.id)
              )
        else { return }
        config.sources.move(fromOffsets: offsets, toOffset: destination)
        editingConfig = config
    }

    /// The selected source's current config id, for display and for the parts
    /// of the form that still speak ids.
    var selectedSourceID: String? {
        sourceHandles.resolve(selectedSource)?.id
    }

    /// The identity currently naming `id`, so a list rendered from the config
    /// can hand its rows an identity.
    func handle(of sourceID: String) -> SourceHandle? {
        sourceHandles.handle(of: sourceID)
    }

    /// The source list to render, each row already carrying its identity, so
    /// the list's selection is an identity rather than an id.
    var sourceRows: [SourceRow] {
        (editingConfig?.sources ?? []).compactMap { source in
            sourceHandles.handle(of: source.id).map { SourceRow(id: $0, source: source) }
        }
    }

    /// The source `handle` names, or nil once it is gone.
    func source(for handle: SourceHandle?) -> SourceConfig? {
        guard let id = sourceHandles.resolve(handle)?.id else { return nil }
        return editingConfig?.sources.first { $0.id == id }
    }

    // MARK: Renaming a source

    /// Points every per-source editor at `handle`.
    ///
    /// The only place `selectedSource` is assigned. Each draft belongs to the
    /// source that was selected when it was typed, so a selection change has to
    /// retire all of them together; doing that in each caller is what let
    /// `addSource` and `removeSelectedSource` move the selection with a filter
    /// draft still in hand.
    ///
    /// - Parameters:
    ///   - committingRename: commit a dirty id draft before moving. False where
    ///     the draft belongs to a row on its way out, or has already landed.
    ///   - keepingFilterDrafts: for a rename, which is the same row under a new
    ///     name rather than a different row.
    private func select(
        _ handle: SourceHandle?,
        committingRename: Bool = false,
        keepingFilterDrafts: Bool = false
    ) {
        if committingRename, commitSourceIDDraft().blocksAction {
            // The name cannot be applied, so the move does not happen: the typed
            // text stays in the field and the reason stays under it. Moving on
            // would take both away, which is the one thing this draft exists to
            // prevent. The list wrote the new selection before this ran, so put
            // it back.
            selectedSource = sourceNameDraft.pending?.handle
            return
        }
        selectedSource = handle
        sourceNameDraft.seed(handle, id: sourceHandles.resolve(handle)?.id)
        if !keepingFilterDrafts {
            titleFilterDrafts.removeAll()
        }
        renameError = nil
    }

    /// Points the draft at `sourceID`, committing whatever was being typed
    /// first.
    ///
    /// Called when the selection changes, so switching rows cannot quietly
    /// discard a half-typed name — and cannot carry it over to the row the user
    /// just clicked either, since the draft resolves against its own
    /// `committedID` rather than against the selection.
    func seedSourceIDDraft(for handle: SourceHandle?) {
        select(handle, committingRename: true)
    }

    /// Judges the accumulated draft text once, on commit — Enter, leaving the
    /// field, switching rows, or saving.
    ///
    /// Never on a keystroke: doing that made the first differing character
    /// count as a rename, so the warning opened mid-word and confirming it
    /// committed a partial id, orphaning every event under the real one.
    ///
    /// Judges the name field on behalf of the source that owns it, whoever
    /// asked. The form's own commit points — saving, switching rows, adding a
    /// source — go through here.
    ///
    /// The result is not discardable. A refused name has to stop the action that
    /// triggered the commit, and `renameError` cannot do that: a caller that
    /// does not read it carries on regardless, which is how adding a source used
    /// to swallow a refusal and how switching rows used to discard the typed
    /// name along with it.
    func commitSourceIDDraft() -> SourceNameCommit {
        // An open confirmation outranks whatever the field says now. Re-judging
        // the text can report `settled` — a retained setter putting the original
        // name back is enough — while the alert is still on screen waiting for
        // an answer about a rename nobody has withdrawn.
        if pendingRename != nil {
            return .awaitingConfirmation
        }
        guard let pending = sourceNameDraft.pending, let config = editingConfig,
              // The field's own source, not whatever currently answers to the
              // id it was seeded with.
              let source = sourceHandles.resolve(pending.handle),
              let index = config.sources.firstIndex(where: { $0.id == source.id })
        else { return .settled }
        let draft = pending.draft
        let others = config.sources.enumerated()
            .filter { $0.offset != index }
            .map(\.element.id)

        switch draft.commit(savedSourceIDs: savedSourceIDs, otherSourceIDs: others) {
        case .unchanged:
            renameError = nil
            sourceNameDraft.revert() // normalizes away stray whitespace
            return .settled
        case let .rejected(reason):
            renameError = reason
            return .rejected(reason: reason)
        case let .apply(newID):
            renameError = nil
            applyRename(source.handle, to: newID)
            return .renamed(newID)
        case let .confirm(from, to):
            renameError = nil
            pendingRename = PendingRename(source: source.handle, from: from, to: to)
            return .awaitingConfirmation
        }
    }

    func confirmPendingRename() {
        guard let rename = pendingRename else { return }
        applyRename(rename.source, to: rename.to)
        pendingRename = nil
    }

    /// Cancelling puts the field back to the id the config still holds, so it
    /// never shows a name that was not applied.
    func cancelPendingRename() {
        pendingRename = nil
        sourceNameDraft.revert()
    }

    private func applyRename(_ handle: SourceHandle, to newID: String) {
        guard var config = editingConfig,
              let oldID = sourceHandles.id(of: handle),
              let index = config.sources.firstIndex(where: { $0.id == oldID }) else { return }
        if let originalID = sourceOrigins.removeValue(forKey: oldID) {
            sourceOrigins[newID] = originalID
        }
        config.sources[index].id = newID
        editingConfig = config
        // Only the id moves. Everything the form keyed by this source — its
        // drafts, its row identities — is keyed by the handle, which a rename
        // does not touch, so there is nothing to carry across.
        sourceHandles.rename(handle, to: newID)
        select(handle, keepingFilterDrafts: true)
    }

    // MARK: Title filters

    /// What the name field shows for `handle`: its own typing, or the source's
    /// current id when the field belongs to a different source.
    func sourceName(of handle: SourceHandle) -> String {
        sourceNameDraft.text(of: handle, fallback: sourceHandles.id(of: handle) ?? "")
    }

    /// Records typing in the name field. Ignored unless `handle` owns it, so a
    /// setter retained from another source cannot rename the one on screen.
    func setSourceName(_ text: String, of handle: SourceHandle) {
        guard sourceHandles.id(of: handle) != nil else { return }
        sourceNameDraft.setText(text, of: handle)
    }

    /// Commits the name field on behalf of `handle` — Return, or the field
    /// losing focus. Ignored unless that source owns the field.
    func commitSourceName(of handle: SourceHandle) {
        guard sourceNameDraft.draft(of: handle) != nil else { return }
        // Nothing follows this commit, and a refusal is already rendered under
        // the field it came from, so there is nothing for the outcome to stop.
        _ = commitSourceIDDraft()
    }

    /// Applies `change` to the source `handle` names, or does nothing once that
    /// source is gone.
    ///
    /// The view builds its controls around a source, and neither its position
    /// nor its id survives editing: a position shifts when the list changes, and
    /// an id can be renamed or taken by a later source. A control still holding
    /// a retired handle resolves to nothing and is ignored.
    func updateSource(_ handle: SourceHandle, _ change: (inout SourceConfig) -> Void) {
        guard let id = sourceHandles.id(of: handle),
              let index = editingConfig?.sources.firstIndex(where: { $0.id == id }) else { return }
        change(&editingConfig!.sources[index])
    }

    /// Every title-filter method takes a source handle, for the same reason.
    func titleFilterEntries(_ field: TitleFilterField, of handle: SourceHandle) -> [String] {
        guard let id = sourceHandles.id(of: handle) else { return [] }
        return editingConfig?.sources.first { $0.id == id }?[keyPath: field.keyPath] ?? []
    }

    /// The draft reads and writes name their source, like every other operation
    /// here. The selection decides what the form RENDERS; it must never decide
    /// what an operation ACTS on, or a callback arriving from one source's
    /// controls works on whichever source is selected by then.
    func titleFilterDraft(_ field: TitleFilterField, of handle: SourceHandle) -> String {
        titleFilterDrafts.text(field.rawValue, of: handle)
    }

    /// Ignored once `handle` is retired: a field built before a rename or a
    /// removal must not be able to re-own the draft.
    func setTitleFilterDraft(_ field: TitleFilterField, to text: String, of handle: SourceHandle) {
        titleFilterDrafts.setText(text, field.rawValue, of: handle, in: sourceHandles)
    }

    func titleFilterDraftCheck(_ field: TitleFilterField, of handle: SourceHandle) -> TitleFilterEntry.Check {
        TitleFilterEntry.check(
            titleFilterDraft(field, of: handle), against: titleFilterEntries(field, of: handle)
        )
    }

    /// The rows to render, each carrying an identity that outlives its
    /// position.
    func titleFilterRows(_ field: TitleFilterField, of handle: SourceHandle) -> [TitleFilterRow] {
        titleFilterRowIDs.rows(
            list(field, handle), entries: titleFilterEntries(field, of: handle)
        )
    }

    /// Adds what is in the field's draft to the source `handle` names. Silent
    /// when the draft is not addable — the button that calls this is disabled in
    /// that state, and the reason is already on screen.
    ///
    /// The add and the clear travel together, taking one resolved source, so no
    /// arrangement of callbacks can add to one source and clear another.
    func addTitleFilter(_ field: TitleFilterField, to handle: SourceHandle) {
        guard let sources = editingConfig?.sources,
              let source = sourceHandles.resolve(handle),
              let committed = TitleFilterEntry.committingDraft(
                  field.rawValue, to: field.keyPath, of: source,
                  in: sources, drafts: titleFilterDrafts
              ) else { return }
        editingConfig?.sources = committed.sources
        titleFilterDrafts = committed.drafts
        titleFilterRowIDs.appended(to: list(field, handle))
    }

    /// Rewrites one row as the user types in it.
    ///
    /// Addressed by row identity within a source addressed by its handle: a
    /// commit can arrive after its row moved, or after its source was renamed or
    /// deleted, and either resolves to nothing rather than to a neighbour.
    func setTitleFilterEntry(
        _ text: String, _ field: TitleFilterField, of handle: SourceHandle, row id: TitleFilterRowID
    ) {
        guard let sources = editingConfig?.sources,
              let sourceID = sourceHandles.id(of: handle),
              let row = position(of: id, field, handle),
              let updated = TitleFilterEntry.setting(
                  text, at: row, in: field.keyPath, ofSourceWith: sourceID, in: sources
              ) else { return }
        editingConfig?.sources = updated
    }

    func removeTitleFilter(_ field: TitleFilterField, from handle: SourceHandle, row id: TitleFilterRowID) {
        guard let sources = editingConfig?.sources,
              let sourceID = sourceHandles.id(of: handle),
              let row = position(of: id, field, handle),
              let updated = TitleFilterEntry.removing(
                  at: row, from: field.keyPath, ofSourceWith: sourceID, in: sources
              ) else { return }
        editingConfig?.sources = updated
        titleFilterRowIDs.removed(at: row, from: list(field, handle))
    }

    /// Why the row identified by `id` cannot be saved, or nil.
    ///
    /// Resolved by identity like every other row operation, so the caption a
    /// row shows always describes that row.
    func titleFilterRowMessage(
        _ field: TitleFilterField, of handle: SourceHandle, row id: TitleFilterRowID
    ) -> String? {
        let entries = titleFilterEntries(field, of: handle)
        guard let row = position(of: id, field, handle), entries.indices.contains(row) else { return nil }
        return TitleFilterEntry.message(
            for: TitleFilterEntry.checkRow(entries[row], against: entries, excluding: row)
        )
    }

    private func list(_ field: TitleFilterField, _ handle: SourceHandle) -> TitleFilterRowIDs.List {
        TitleFilterRowIDs.List(source: handle, field: field.rawValue)
    }

    private func position(
        of id: TitleFilterRowID, _ field: TitleFilterField, _ handle: SourceHandle
    ) -> Int? {
        titleFilterRowIDs.position(
            of: id, in: list(field, handle), count: titleFilterEntries(field, of: handle).count
        )
    }

    /// Gives every list on screen an identity per row. Idempotent, so calling
    /// it again cannot re-key a row under a live text field.
    private func seedTitleFilterRowIDs() {
        guard let config = editingConfig else { return }
        for source in config.sources {
            guard let handle = sourceHandles.handle(of: source.id) else { continue }
            for field in TitleFilterField.allCases {
                titleFilterRowIDs.seed(
                    list(field, handle), count: source[keyPath: field.keyPath].count
                )
            }
        }
    }

    /// Trims every entry, the way the add field already does.
    ///
    /// Run at the save commit point rather than per keystroke, so a space typed
    /// mid-word is not eaten while the user is still typing.
    func normalizeTitleFilters() {
        guard var config = editingConfig else { return }
        for index in config.sources.indices {
            for field in TitleFilterField.allCases {
                config.sources[index][keyPath: field.keyPath] = TitleFilterEntry.normalized(
                    config.sources[index][keyPath: field.keyPath]
                )
            }
        }
        editingConfig = config
    }

    /// Why the title filters cannot be saved yet, or nil. Covers both a row
    /// edited to blank in place and a draft typed but never added: dropping
    /// either one silently at save time is the failure this guards.
    var titleFilterProblem: String? {
        guard let config = editingConfig else { return nil }
        for source in config.sources {
            for field in TitleFilterField.allCases {
                if let problem = TitleFilterEntry.problem(in: source[keyPath: field.keyPath]) {
                    return "\(field.errorLabel) for “\(source.id)”: \(problem)"
                }
            }
        }
        guard let selected = selectedSource, sourceHandles.id(of: selected) != nil else { return nil }
        for field in TitleFilterField.allCases {
            if let message = TitleFilterEntry.message(for: titleFilterDraftCheck(field, of: selected)) {
                return "\(field.errorLabel): \(message)"
            }
        }
        return nil
    }

    // MARK: Saving

    /// Writes through the same writer everything else uses — comment
    /// preserving, self-checked, backed up. Never a UI-only write path.
    func saveSettings() {
        // Save is a commit point for the id field too. Without this, a name
        // typed but never submitted is silently dropped by the save it looks
        // like it was part of.
        if commitSourceIDDraft().blocksAction {
            return
        }
        // A refused id or an open warning has to be resolved first, otherwise
        // saving writes the old id while the field still shows the new one.
        guard renameError == nil, pendingRename == nil else { return }

        // Same commit point for the list editors: an entry typed but never
        // added would otherwise vanish with the save that looked like it
        // included it.
        if let selected = selectedSource {
            for field in TitleFilterField.allCases {
                addTitleFilter(field, to: selected)
            }
        }
        // A row edited in place never went through `adding`, so this is where
        // its padding comes off. Before the problem check, since trimming can
        // turn "   " into an empty row that must refuse the save.
        normalizeTitleFilters()
        // Never reachable through the form, which disables Save on a problem —
        // but the writer's validation would name a config field rather than the
        // row that caused it, so the readable message is produced here.
        if let problem = titleFilterProblem {
            saveError = problem
            return
        }

        guard let config = editingConfig else { return }
        do {
            let outcome = try services.saveConfig(config, sourceOrigins)
            saveError = nil
            saveWarning = outcome.warning
            savedSourceIDs = Set(config.sources.map(\.id))
            configError = nil
            // Immediately, not at the next pass: a user who just switched
            // "React to calendar changes" off expects it off now, and with a
            // long interval the next pass could be many minutes away.
            reconcileChangeObservation()
            // Config is re-read at the start of every pass, so the change takes
            // effect on the next sync with no restart.
            closeSettings()
        } catch {
            saveError = error.localizedDescription
        }
        refreshState()
    }
}

/// Which of a source's two title-filter lists a control is editing.
enum TitleFilterField: String, CaseIterable, Hashable {
    case matches
    case excludes

    var keyPath: WritableKeyPath<SourceConfig, [String]> {
        switch self {
        case .matches: \.titleMatches
        case .excludes: \.titleExcludes
        }
    }

    var title: String {
        switch self {
        case .matches: "Only mirror titles containing"
        case .excludes: "Never mirror titles containing"
        }
    }

    /// What an empty list means for THIS list.
    ///
    /// Scoped to the one filter, because the two of them compose: an empty
    /// only-mirror list drops its own gate, it does not promise that every
    /// event is mirrored — the never-mirror list, the weekday and duration
    /// rules, and the all-day setting all still apply.
    var emptyMeaning: String {
        switch self {
        case .matches: "Empty: this list does not filter anything out."
        case .excludes: "Empty: this list does not exclude anything."
        }
    }

    /// Names the list in a control's accessibility label. Both lists have a
    /// `+` and a row of `−` buttons, and "Add entry" on each says nothing about
    /// which list is being added to.
    var accessibilityName: String {
        switch self {
        case .matches: "only-mirror list"
        case .excludes: "never-mirror list"
        }
    }

    /// Names the list in a message that appears away from it, in the footer.
    var errorLabel: String {
        switch self {
        case .matches: "Only-mirror list"
        case .excludes: "Never-mirror list"
        }
    }

    /// The add field's prompt.
    ///
    /// Never a plausible entry: `"1:1"` as placeholder text sat directly under
    /// a real `1:1` row and read as a second one. The two fields also differ
    /// from each other, so a screenshot of the pair is unambiguous.
    var addPlaceholder: String {
        switch self {
        case .matches: "Add a word or phrase…"
        case .excludes: "Add a word to exclude…"
        }
    }
}

/// One row of the source list: the source, and the identity the form addresses
/// it by.
struct SourceRow: Identifiable {
    let id: SourceHandle
    let source: SourceConfig
}

struct PendingRename: Equatable {
    /// The source being renamed, by identity. A position would be stale by the
    /// time the user answers the alert; so would the id, which is the thing
    /// being changed.
    let source: SourceHandle
    let from: String
    let to: String
}
