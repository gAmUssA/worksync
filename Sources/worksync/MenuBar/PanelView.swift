import ServiceManagement
import SwiftUI
import WorkSyncCore

/// Every `#available(macOS 26, *)` check in the menu bar lives here, paired
/// with its back-deployed equivalent, so no view below ever contains an
/// availability branch (SPEC §11).
/// `#available` is a RUNTIME check — the symbol still has to exist when the
/// code is compiled, and `glassEffect` does not exist in the macOS 15 SDK. So
/// each helper is gated twice: `#if compiler(>=6.2)` decides whether the modern
/// path is compiled at all (Swift 6.2 ships with the macOS 26 SDK), and
/// `#available` decides whether it is taken at runtime. Without the outer
/// guard the project simply does not build on an older toolchain.
extension View {
    @ViewBuilder
    func barGlass() -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26, *) {
                glassEffect(.regular, in: Rectangle())
            } else {
                background(.bar)
            }
        #else
            background(.bar)
        #endif
    }

    @ViewBuilder
    func glassButton() -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26, *) {
                buttonStyle(.glass)
            } else {
                buttonStyle(.bordered)
            }
        #else
            buttonStyle(.bordered)
        #endif
    }
}

extension View {
    /// The panel's own ground.
    ///
    /// The NSPanel is deliberately transparent so its rounded corners are not
    /// drawn over, which means the SwiftUI content is the only thing painting a
    /// background. Without this the panel is literally see-through to the
    /// desktop, and the cards — which are designed to sit on a window
    /// background — have nothing to sit on.
    func panelBackground() -> some View {
        background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Design tokens, kept in one place so the panel reads as one surface.
enum Theme {
    static let width: CGFloat = 320
    static let padding: CGFloat = 14
    static let cardRadius: CGFloat = 12
    static let barHeight: CGFloat = 44
}

struct PanelView: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        Group {
            if model.screen == .settings {
                SettingsView(model: model)
            } else {
                dashboard
            }
        }
        // A pure offset, never a .transition carrying .opacity: compositing
        // into a transparency layer leaves .quaternary material with no vibrant
        // backdrop to sample, so it resolves to its opaque near-white base and
        // flashes white across the cards (SPEC §11).
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: model.screen)
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            header
            // Shown here rather than in the settings footer because a
            // successful save closes that screen immediately, which would
            // dismiss the warning before it had been read.
            if let warning = model.saveWarning {
                saveWarningBanner(warning)
            }
            Divider()
            healthSection
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: Theme.width)
        .panelBackground()
    }

    /// The green/red answer to "is anything wrong", with the failing checks
    /// and their fixes underneath.
    ///
    /// Rendered from the same `DoctorReport` the CLI prints — the CLI computes,
    /// this displays — so the two can never disagree about what healthy means.
    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: healthSymbol)
                    .foregroundStyle(healthTint)
                Text("Health").font(.subheadline).bold()
                Spacer()
                if model.isCheckingHealth {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        model.refreshHealth()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Re-check health")
                }
            }

            Text(model.healthSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(model.healthProblems, id: \.id) { problem in
                problemRow(problem)
            }
        }
        .padding(Theme.padding)
    }

    private func problemRow(_ problem: DoctorFinding) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(problem.severity.glyph)
                    .foregroundStyle(problem.severity == .error ? .red : .orange)
                Text(problem.title).font(.callout)
            }
            ForEach(problem.detail, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let destination = DoctorDestination.forFinding(id: problem.id) {
                Button(destination.buttonTitle) { model.open(destination) }
                    .controlSize(.small)
            } else if let remediation = problem.remediation {
                // No destination to send them to, so show the command rather
                // than a button that cannot do anything.
                Text(remediation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(.quaternary))
        )
    }

    private var healthSymbol: String {
        switch model.health?.worstSeverity {
        case .error: "xmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .ok, .skipped: "checkmark.circle.fill"
        // Never green before the first run: an unknown state shown as healthy
        // is the failure this section exists to prevent.
        case nil: "questionmark.circle"
        }
    }

    private var healthTint: Color {
        switch model.health?.worstSeverity {
        case .error: .red
        case .warning: .orange
        case .ok, .skipped: .green
        case nil: .secondary
        }
    }

    private func saveWarningBanner(_ warning: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(warning)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                model.saveWarning = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, Theme.padding)
        .padding(.bottom, 8)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: model.state.symbolName)
                    .foregroundStyle(model.state == .error ? .red : .secondary)
                Text("WorkSync")
                    .font(.headline)
                Spacer()
                if model.isSyncing {
                    ProgressView().controlSize(.small)
                }
            }
            // Ticks on its own clock so "synced 4m ago" stays true without
            // waiting for the next pass — and only while the panel is visible.
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(model.headerLine)
                    .font(.caption)
                    .foregroundStyle(model.state == .error ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.padding)
    }

    @ViewBuilder
    private var content: some View {
        if model.sourceCounts.isEmpty {
            Text("No sources have run yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.padding)
        } else {
            VStack(spacing: 6) {
                ForEach(model.sourceCounts.keys.sorted(), id: \.self) { sourceID in
                    HStack {
                        Text(sourceID).font(.callout)
                        Spacer()
                        Text("\(model.sourceCounts[sourceID] ?? 0) events")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cardRadius)
                            // The System Settings grouped-box look, from system
                            // colors only — no hand-tuned hexes, so light/dark
                            // and accessibility settings track automatically.
                            .fill(Color(nsColor: .textBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.cardRadius)
                                    .fill(.quaternary)
                            )
                    )
                }
            }
            .padding(Theme.padding)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Sync now") { model.syncNow() }
                .glassButton()
                .disabled(model.isSyncing || model.isPaused)

            Button(model.isPaused ? "Resume" : "Pause") { model.isPaused.toggle() }
                .glassButton()

            Spacer()

            Menu {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { _ in model.toggleLaunchAtLogin() }
                ))
                if model.loginItemStatus == .requiresApproval {
                    Text("Needs approval in System Settings")
                }
                Divider()
                Button("Settings…") { model.openSettings() }
                Button("Open config") { model.openConfig() }
                Button("Open log") { model.openLog() }
                Divider()
                Button("Quit WorkSync") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, Theme.padding)
        .frame(height: Theme.barHeight)
        .barGlass()
    }
}
