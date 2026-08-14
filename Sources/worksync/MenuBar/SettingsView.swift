import SwiftUI
import WorkSyncCore

/// Settings lives inside the panel as a screen rather than in its own window.
///
/// That is less code than a window, reads better for a menu bar utility, and
/// removes a whole class of accessory-app problems: no activation dance to
/// bring a window forward, and no NavigationSplitView-in-a-plain-NSWindow
/// sidebar defect (SPEC §11.1).
struct SettingsView: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if let blocked = model.settingsBlocked {
                blockedNotice(blocked)
            } else if model.editingConfig != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        generalSection
                        targetSection
                        sourcesSection
                        sourceDetail
                    }
                    .padding(Theme.padding)
                }
                .frame(maxHeight: 420)
            }
            Divider()
            footer
        }
        // A fixed height per screen, so the panel has exactly two stable sizes
        // and resizing only happens on a screen change. SPEC §11.1 allows this
        // simplified version of the auto-fitting panel.
        .frame(width: Theme.width, height: 560)
        .alert(
            "Rename this source?",
            isPresented: Binding(
                get: { model.pendingRename != nil },
                set: {
                    if !$0 {
                        model.cancelPendingRename()
                    }
                }
            )
        ) {
            Button("Rename", role: .destructive) { model.confirmPendingRename() }
            Button("Cancel", role: .cancel) { model.cancelPendingRename() }
        } message: {
            if let rename = model.pendingRename {
                Text(
                    "Every blocker WorkSync created carries the source id, which is how it "
                        + "recognizes its own events. Renaming “\(rename.from)” to “\(rename.to)” orphans all of "
                        + "them: they will never be updated or removed by a normal sync.\n\n"
                        + "Recover them afterwards with:\nworksync purge --source \(rename.from)"
                )
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                model.closeSettings()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Settings").font(.headline)
            Spacer()
            // Balances the back button so the title stays centered.
            Label("Back", systemImage: "chevron.left").opacity(0).accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.padding)
        .frame(height: Theme.barHeight)
    }

    private func blockedNotice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
            Button("Open config") { model.openConfig() }
        }
        .padding(Theme.padding)
    }

    // MARK: General

    @ViewBuilder
    private var generalSection: some View {
        if let config = model.editingConfig {
            card("General") {
                stepper("Sync horizon", value: Binding(
                    get: { config.general.windowDays },
                    set: { model.editingConfig?.general.windowDays = $0 }
                ), range: 1 ... 365, suffix: "days")

                stepper("Run every", value: Binding(
                    get: { config.general.intervalMinutes },
                    set: { model.editingConfig?.general.intervalMinutes = $0 }
                ), range: 1 ... 1440, suffix: "min")

                picker("Notifications", selection: Binding(
                    get: { config.general.notify },
                    set: { model.editingConfig?.general.notify = $0 }
                ), options: NotifyMode.allCases, label: \.rawValue)

                picker("Log level", selection: Binding(
                    get: { config.general.logLevel },
                    set: { model.editingConfig?.general.logLevel = $0 }
                ), options: LogLevel.allCases, label: \.rawValue)

                Toggle("React to calendar changes", isOn: Binding(
                    get: { config.general.changeDriven },
                    set: { model.editingConfig?.general.changeDriven = $0 }
                ))
                .font(.callout)
            }
        }
    }

    // MARK: Target

    @ViewBuilder
    private var targetSection: some View {
        if let config = model.editingConfig {
            card("Blockers are written to") {
                calendarPickers(
                    account: Binding(
                        get: { config.target.account },
                        set: { model.editingConfig?.target.account = $0 }
                    ),
                    calendar: Binding(
                        get: { config.target.calendar },
                        set: { model.editingConfig?.target.calendar = $0 }
                    ),
                    writableOnly: true
                )
            }
        }
    }

    // MARK: Sources

    @ViewBuilder
    private var sourcesSection: some View {
        if let config = model.editingConfig {
            card("Sources") {
                Text("The first source listed wins when the same event appears in two of them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Drag to reorder, because order decides dedup (SPEC §4.1).
                List(selection: $model.selectedSourceID) {
                    ForEach(config.sources, id: \.id) { source in
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                            Text(source.id)
                            Spacer()
                            Text(source.calendar).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(source.id)
                    }
                    .onMove { model.moveSources(from: $0, to: $1) }
                }
                .frame(height: 110)
                .scrollContentBackground(.hidden)

                HStack(spacing: 6) {
                    // A visible pair, since swipe-to-delete alone is not a
                    // discoverable macOS interaction (SPEC §11.1).
                    Button { model.addSource() } label: { Image(systemName: "plus") }
                    Button { model.removeSelectedSource() } label: { Image(systemName: "minus") }
                        .disabled(model.selectedSourceID == nil)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var sourceDetail: some View {
        if let config = model.editingConfig,
           let selected = model.selectedSourceID,
           let index = config.sources.firstIndex(where: { $0.id == selected }) {
            let source = config.sources[index]
            card("“\(source.id)” settings") {
                LabeledContent("Name") {
                    TextField("id", text: Binding(
                        get: { source.id },
                        set: { model.requestRename(of: selected, to: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
                .font(.callout)

                calendarPickers(
                    account: Binding(
                        get: { source.account },
                        set: { model.editingConfig?.sources[index].account = $0 }
                    ),
                    calendar: Binding(
                        get: { source.calendar },
                        set: { model.editingConfig?.sources[index].calendar = $0 }
                    ),
                    writableOnly: false
                )

                LabeledContent("Shown as") {
                    TextField("Busy", text: Binding(
                        get: { source.titleTemplate },
                        set: { model.editingConfig?.sources[index].titleTemplate = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
                .font(.callout)

                stepper("Pad before", value: Binding(
                    get: { source.paddingBeforeMinutes },
                    set: { model.editingConfig?.sources[index].paddingBeforeMinutes = $0 }
                ), range: 0 ... 480, suffix: "min")

                stepper("Pad after", value: Binding(
                    get: { source.paddingAfterMinutes },
                    set: { model.editingConfig?.sources[index].paddingAfterMinutes = $0 }
                ), range: 0 ... 480, suffix: "min")

                stepper("Ignore shorter than", value: Binding(
                    get: { source.minDurationMinutes },
                    set: { model.editingConfig?.sources[index].minDurationMinutes = $0 }
                ), range: 0 ... 480, suffix: "min")

                Toggle("Merge nearby events", isOn: Binding(
                    get: { source.coalesce },
                    set: { model.editingConfig?.sources[index].coalesce = $0 }
                )).font(.callout)

                Toggle("Include all-day events", isOn: Binding(
                    get: { source.includeAllDay },
                    set: { model.editingConfig?.sources[index].includeAllDay = $0 }
                )).font(.callout)

                Toggle("Skip when work is already busy", isOn: Binding(
                    get: { source.skipIfWorkBusy },
                    set: { model.editingConfig?.sources[index].skipIfWorkBusy = $0 }
                )).font(.callout)

                picker("Shows as", selection: Binding(
                    get: { source.availability },
                    set: { model.editingConfig?.sources[index].availability = $0 }
                ), options: Availability.allCases, label: \.rawValue)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if let saveError = model.saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
            Button("Cancel") { model.closeSettings() }
                .glassButton()
            Button("Save") { model.saveSettings() }
                .glassButton()
                .keyboardShortcut(.defaultAction)
                .disabled(model.editingConfig == nil)
        }
        .padding(.horizontal, Theme.padding)
        .frame(height: Theme.barHeight)
        .barGlass()
    }

    // MARK: Building blocks

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).bold()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(.quaternary))
        )
    }

    private func stepper(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        suffix: String
    ) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue) \(suffix)").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private func picker<Option: Hashable>(
        _ title: String,
        selection: Binding<Option>,
        options: [Option],
        label: KeyPath<Option, String>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(options, id: \.self) { option in
                Text(option[keyPath: label]).tag(option)
            }
        }
        .font(.callout)
    }

    /// Account and calendar are popups fed by the same enumeration
    /// `worksync calendars` prints. A free-text typo hard-errors the whole
    /// sync; a popup cannot be wrong (SPEC §11.1).
    @ViewBuilder
    private func calendarPickers(
        account: Binding<String>,
        calendar: Binding<String>,
        writableOnly: Bool
    ) -> some View {
        let accounts = model.accountChoices
        let calendars = writableOnly
            ? model.writableCalendarChoices(inAccount: account.wrappedValue)
            : model.calendarChoices(inAccount: account.wrappedValue)

        if accounts.isEmpty {
            Text("No calendars available — grant calendar access first.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Picker("Account", selection: account) {
                // The saved value may name an account that no longer exists;
                // keeping it in the list stops the picker silently rewriting
                // config to something the user never chose.
                if !accounts.contains(account.wrappedValue) {
                    Text("\(account.wrappedValue) (not found)").tag(account.wrappedValue)
                }
                ForEach(accounts, id: \.self) { Text($0).tag($0) }
            }
            .font(.callout)

            Picker("Calendar", selection: calendar) {
                if !calendars.contains(calendar.wrappedValue) {
                    Text("\(calendar.wrappedValue) (not found)").tag(calendar.wrappedValue)
                }
                ForEach(calendars, id: \.self) { Text($0).tag($0) }
            }
            .font(.callout)
        }
    }
}
