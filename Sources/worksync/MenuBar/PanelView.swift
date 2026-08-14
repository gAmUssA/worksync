import SwiftUI
import WorkSyncCore

/// Every `#available(macOS 26, *)` check in the menu bar lives here, paired
/// with its back-deployed equivalent, so no view below ever contains an
/// availability branch (SPEC §11).
extension View {
    @ViewBuilder
    func barGlass() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: Rectangle())
        } else {
            background(.bar)
        }
    }

    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
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
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: Theme.width)
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
