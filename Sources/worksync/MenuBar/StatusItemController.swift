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
    private var observation: NSKeyValueObservation?

    init(model: MenuBarModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        configureStatusItem()
        startScheduler()
        observeWake()
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
        for (title, selector) in [
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

    // MARK: Panel

    private func togglePanel() {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
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

    /// Redraws the icon shortly after state changes. Debounced rather than
    /// bound to every mutation: a burst of writes during a pass can otherwise
    /// make the status item visibly flicker or disappear (SPEC §11).
    private func scheduleIconRefresh() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.renderIcon() }
        }
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.renderIcon() }
        }
    }
}
