import AppKit
import SwiftUI
import WorkSyncCore

/// A panel that can take keyboard focus without activating the app.
///
/// Not `NSPopover`: a popover's window is key only while the whole app is
/// active, and activating an LSUIElement accessory is asynchronous — the panel
/// ends up on screen but not key, so the first keystroke goes to the status
/// button and the user has to click twice. Not `MenuBarExtra` either: it is a
/// Scene, conflicting with the NSApplication + delegate lifecycle this process
/// owns, and it never becomes a proper key window for text input (SPEC §11.0).
final class MenuBarPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

@MainActor
final class StatusItemController: NSObject {
    private let model: MenuBarModel
    private let statusItem: NSStatusItem
    private var panel: MenuBarPanel?
    private var hostingController: NSHostingController<PanelView>?

    private var timer: Timer?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var iconRefreshTimer: Timer?
    private var appearanceObservation: NSKeyValueObservation?

    init(model: MenuBarModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        configureStatusItem()
        observeModel()
        startScheduler()
        observeWake()
        observeAppearance()
        renderIcon()
    }

    deinit {
        timer?.invalidate()
    }

    /// Whether AppKit actually gave us a status item button — the difference
    /// between "no icon because the delegate never ran" and "no icon because a
    /// menu bar manager is hiding it".
    var hasStatusItemButton: Bool {
        statusItem.button != nil
    }

    // MARK: Status item

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusButtonClicked)
        // One action handles both buttons; the handler branches on the event.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func renderIcon() {
        guard let button = statusItem.button else { return }
        let image = NSImage(
            systemSymbolName: model.state.symbolName,
            accessibilityDescription: model.state.accessibilityLabel
        )
        // Template so it adapts to light and dark menu bars (SPEC §11).
        image?.isTemplate = true
        button.image = image
        button.toolTip = model.headerLine
    }

    @objc private func statusButtonClicked() {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        if isRightClick {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    /// The same actions in plain-menu form. A custom panel cannot be driven by
    /// VoiceOver or the keyboard as reliably as a real NSMenu, and this is the
    /// escape hatch if the panel itself ever misbehaves (SPEC §11.0).
    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: model.headerLine, action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let sync = NSMenuItem(title: "Sync Now", action: #selector(syncNow), keyEquivalent: "")
        sync.target = self
        sync.isEnabled = !model.isSyncing && !model.isPaused
        menu.addItem(sync)

        let pause = NSMenuItem(
            title: model.isPaused ? "Resume Syncing" : "Pause Syncing",
            action: #selector(togglePause), keyEquivalent: ""
        )
        pause.target = self
        menu.addItem(pause)

        menu.addItem(.separator())
        // Status is read live every time the menu is built, never cached
        // across openings (SPEC §10).
        model.refreshLoginItemStatus()
        let login = NSMenuItem(
            title: "Launch at Login (\(model.loginItemDescription))",
            action: #selector(toggleLaunchAtLogin), keyEquivalent: ""
        )
        login.target = self
        login.state = model.launchesAtLogin ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        for (title, selector) in [
            ("Settings…", #selector(openSettings)),
            ("Open Config", #selector(openConfig)),
            ("Open Log", #selector(openLog)),
        ] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit WorkSync", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Cleared immediately, or left-click would open this menu instead of
        // toggling the panel.
        statusItem.menu = nil
    }

    @objc private func syncNow() {
        model.syncNow(); scheduleIconRefresh()
    }

    @objc private func togglePause() {
        model.isPaused.toggle(); renderIcon()
    }

    @objc private func openConfig() {
        model.openConfig(); renderIcon()
    }

    @objc private func openLog() {
        model.openLog()
    }

    @objc private func openSettings() {
        model.openSettings()
        showPanel()
    }

    @objc private func toggleLaunchAtLogin() {
        // Surfaced as an alert rather than swallowed: .requiresApproval needs
        // the user to do something in System Settings, and silently doing
        // nothing visible is how people conclude the toggle is broken.
        if let message = model.toggleLaunchAtLogin() {
            let alert = NSAlert()
            alert.messageText = "Launch at login"
            alert.informativeText = message
            alert.runModal()
        }
    }

    // MARK: Panel

    private func togglePanel() {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        // Never show a remembered value: the user may have changed it in
        // System Settings since the panel was last open.
        model.refreshLoginItemStatus()

        let controller = hostingController ?? {
            let created = NSHostingController(rootView: PanelView(model: model))
            hostingController = created
            return created
        }()

        let panel = panel ?? makePanel(content: controller)
        self.panel = panel

        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        // Lay out before showing, or the first frame flashes at the wrong size.
        controller.view.layoutSubtreeIfNeeded()
        let size = controller.view.fittingSize
        panel.setContentSize(size)

        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let origin = NSPoint(
            x: buttonRect.midX - size.width / 2,
            y: buttonRect.minY - size.height - 6
        )
        panel.setFrameOrigin(clampToScreen(origin, size: size, near: buttonRect))
        panel.makeKeyAndOrderFront(nil)

        installDismissMonitors()
    }

    /// Re-fits the panel to its content, keeping the TOP edge pinned so it
    /// grows downward from the menu bar rather than drifting up off screen.
    private func resizePanelToFit() {
        guard let panel, panel.isVisible, let controller = hostingController else { return }
        controller.view.layoutSubtreeIfNeeded()
        let size = controller.view.fittingSize
        guard size.width > 0, size.height > 0, size != panel.frame.size else { return }

        let top = panel.frame.maxY
        var frame = panel.frame
        frame.size = size
        frame.origin.y = top - size.height
        panel.setFrame(frame, display: true, animate: false)
    }

    private func makePanel(content: NSHostingController<PanelView>) -> MenuBarPanel {
        let panel = MenuBarPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = content
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Pin the appearance to the system's rather than leaving it unset.
        // An unset panel appearance resolves to Aqua, so in Dark Mode the
        // content renders light-mode colours — dark text and white cards — on
        // a dark backdrop, which is illegible (SPEC §11).
        panel.appearance = NSApp.effectiveAppearance
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 13
        panel.contentView?.layer?.cornerCurve = .continuous
        panel.contentView?.layer?.masksToBounds = true
        return panel
    }

    private func clampToScreen(_ origin: NSPoint, size: NSSize, near button: NSRect) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(button) }) ?? NSScreen.main
        else { return origin }
        let visible = screen.visibleFrame
        var point = origin
        point.x = min(max(point.x, visible.minX + 8), visible.maxX - size.width - 8)
        point.y = max(point.y, visible.minY + 8)
        return point
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        removeDismissMonitors()

        // The SwiftUI tree survives orderOut, so transient state has to be
        // reset explicitly or it reappears looking stale (SPEC §11.0).
        if let window = panel, let responder = window.firstResponder,
           !(responder is NSTextView) {
            window.makeFirstResponder(nil)
        }
    }

    // MARK: Dismissal

    private func installDismissMonitors() {
        removeDismissMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated { self?.handleOutsideClick(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated { self?.handleOutsideClick(event) }
            return event
        }
    }

    private func removeDismissMonitors() {
        [localMonitor, globalMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        localMonitor = nil
        globalMonitor = nil
    }

    private func handleOutsideClick(_ event: NSEvent) {
        guard panel?.isVisible == true else { return }
        if PanelDismissPolicy.shouldKeepOpen(
            eventWindowClassName: event.window.map { String(describing: type(of: $0)) },
            isPanelWindow: event.window === panel,
            hitsStatusButton: hitsStatusButton(event)
        ) {
            return
        }
        hidePanel()
    }

    private func hitsStatusButton(_ event: NSEvent) -> Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        else { return false }
        return PanelDismissPolicy.pointHitsStatusButton(
            point: (x: point.x, y: point.y),
            buttonRect: (minX: rect.minX, maxX: rect.maxX, minY: rect.minY),
            screenMaxY: screen.frame.maxY
        )
    }

    // MARK: Scheduling

    private func startScheduler() {
        let interval = TimeInterval(max(1, model.intervalMinutes) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.syncNow()
                self?.scheduleIconRefresh()
            }
        }
        // A pass on launch, so the first window after login is covered.
        model.syncNow()
        scheduleIconRefresh()
    }

    /// Follows system Light/Dark switches. The panel's appearance is pinned, so
    /// without this it would keep whatever the theme was when it was created.
    private func observeAppearance() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] app, _ in
            Task { @MainActor [weak self] in
                self?.panel?.appearance = app.effectiveAppearance
            }
        }
    }

    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Arrives on an arbitrary queue's main delivery; hop explicitly.
            MainActor.assumeIsolated {
                self?.model.syncNow()
                self?.scheduleIconRefresh()
            }
        }
    }

    /// Re-renders the icon whenever anything it displays changes.
    ///
    /// `onChange` is ONE-SHOT: without re-arming, the icon updates once and
    /// then never again. This is the whole mechanism — a pass that finishes
    /// asynchronously has no other way to reach the status item, so without it
    /// the icon sticks on "syncing" until the next timer tick.
    private func observeModel() {
        withObservationTracking {
            _ = model.state
            _ = model.lastRun
            _ = model.configError
            // Screen changes the panel's size, so it has to be observed too or
            // the settings screen opens clipped to the dashboard's height.
            _ = model.screen
        } onChange: { [weak self] in
            // onChange fires BEFORE the mutation is visible, so the render has
            // to happen on a later turn of the run loop — which the debounce
            // below provides anyway.
            Task { @MainActor [weak self] in
                self?.scheduleIconRefresh()
                self?.resizePanelToFit()
                self?.observeModel()
            }
        }
    }

    /// Coalesces bursts into one render. A pass writes several properties in
    /// quick succession, and re-rendering on each can make the status item
    /// visibly flicker or briefly disappear.
    private func scheduleIconRefresh() {
        iconRefreshTimer?.invalidate()
        iconRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.renderIcon() }
        }
    }
}
