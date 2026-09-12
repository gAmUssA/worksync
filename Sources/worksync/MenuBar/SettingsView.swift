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
    /// Leaving the id field is a commit point, the same as pressing Return.
    @FocusState private var idFieldFocused: Bool

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
        .panelBackground()
        .onChange(of: idFieldFocused) { wasFocused, isFocused in
            // Only on the way out. Committing on focus gain would judge the
            // text the moment the user clicked into the field.
            //
            // The outcome is deliberately unused: leaving the field starts
            // nothing that a refusal would have to stop, and the reason is
            // rendered under the field either way.
            if wasFocused, !isFocused {
                _ = model.commitSourceIDDraft()
            }
        }
        .onChange(of: model.selectedSource) { _, newValue in
            // Points the draft at the newly selected row, committing any
            // half-typed name first so it is neither lost nor carried across.
            model.seedSourceIDDraft(for: newValue)
        }
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
        if model.editingConfig != nil {
            card("Sources") {
                Text("The first source listed wins when the same event appears in two of them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Drag to reorder, because order decides dedup (SPEC §4.1).
                // Selection is an identity, not an id: the id is editable and
                // a removed one can be taken by a later source.
                // The rows the drag's offsets will be computed against, held
                // so the drop can be checked against the list it was drawn on.
                let rows = model.sourceRows
                List(selection: $model.selectedSource) {
                    ForEach(rows) { row in
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                            Text(row.source.id)
                            Spacer()
                            Text(row.source.calendar).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(row.id)
                    }
                    .onMove { model.moveSources(from: $0, to: $1, rendered: rows.map(\.id)) }
                }
                .frame(height: 110)
                .scrollContentBackground(.hidden)

                HStack(spacing: 6) {
                    // A visible pair, since swipe-to-delete alone is not a
                    // discoverable macOS interaction (SPEC §11.1).
                    Button { model.addSource() } label: { Image(systemName: "plus") }
                    Button { model.removeSelectedSource() } label: { Image(systemName: "minus") }
                        .disabled(model.selectedSource == nil)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var sourceDetail: some View {
        if let handle = model.selectedSource, let source = model.source(for: handle) {
            card("“\(source.id)” settings") {
                LabeledContent("Name") {
                    // Bound to the draft, never straight to the config: routing
                    // keystrokes at the rename policy made the first differing
                    // character open the orphan warning, and the field could
                    // not accumulate a new name at all (SPEC §11.1). Addressed
                    // by this card's handle like every other control here, so a
                    // setter retained from another source cannot rename this one.
                    TextField("id", text: Binding(
                        get: { model.sourceName(of: handle) },
                        set: { model.setSourceName($0, of: handle) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .focused($idFieldFocused)
                    .onSubmit { model.commitSourceName(of: handle) }
                }
                .font(.callout)

                if let renameError = model.renameError {
                    Text(renameError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                calendarPickers(
                    account: Binding(
                        get: { source.account },
                        set: { value in model.updateSource(handle) { $0.account = value } }
                    ),
                    calendar: Binding(
                        get: { source.calendar },
                        set: { value in model.updateSource(handle) { $0.calendar = value } }
                    ),
                    writableOnly: false
                )

                targetCalendarPicker(handle, source: source)

                LabeledContent("Shown as") {
                    TextField("Busy", text: Binding(
                        get: { source.titleTemplate },
                        set: { value in model.updateSource(handle) { $0.titleTemplate = value } }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
                .font(.callout)

                stepper("Pad before", value: Binding(
                    get: { source.paddingBeforeMinutes },
                    set: { value in model.updateSource(handle) { $0.paddingBeforeMinutes = value } }
                ), range: 0 ... 480, suffix: "min")

                stepper("Pad after", value: Binding(
                    get: { source.paddingAfterMinutes },
                    set: { value in model.updateSource(handle) { $0.paddingAfterMinutes = value } }
                ), range: 0 ... 480, suffix: "min")

                stepper("Ignore shorter than", value: Binding(
                    get: { source.minDurationMinutes },
                    set: { value in model.updateSource(handle) { $0.minDurationMinutes = value } }
                ), range: 0 ... 480, suffix: "min")

                // `0` is "no limit", not zero minutes, so the value is rendered
                // rather than printed.
                Stepper(value: Binding(
                    get: { source.maxDurationMinutes },
                    set: { value in model.updateSource(handle) { $0.maxDurationMinutes = value } }
                ), in: 0 ... 1440) {
                    HStack {
                        Text("Ignore longer than")
                        Spacer()
                        Text(SourceFieldRules.maxDurationDescription(source.maxDurationMinutes))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .accessibilityLabel("Ignore events longer than")

                if let problem = SourceFieldRules.maxDurationProblem(
                    max: source.maxDurationMinutes, min: source.minDurationMinutes
                ) {
                    Text(problem).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Merge nearby events", isOn: Binding(
                    get: { source.coalesce },
                    set: { value in model.updateSource(handle) { $0.coalesce = value } }
                )).font(.callout)

                // Nested under the toggle it depends on: the gap decides when
                // two events become one blocker, which only happens while
                // merging is on.
                VStack(alignment: .leading, spacing: 2) {
                    stepper("Merge when closer than", value: Binding(
                        get: { source.coalesceGapMinutes },
                        set: { value in model.updateSource(handle) { $0.coalesceGapMinutes = value } }
                    ), range: 0 ... 480, suffix: "min")
                        .disabled(!SourceFieldRules.coalesceGapApplies(coalesce: source.coalesce))
                        .accessibilityLabel("Merge events closer together than")

                    if !SourceFieldRules.coalesceGapApplies(coalesce: source.coalesce) {
                        Text(SourceFieldRules.coalesceGapUnusedNote)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 12)

                Toggle("Include all-day events", isOn: Binding(
                    get: { source.includeAllDay },
                    set: { value in model.updateSource(handle) { $0.includeAllDay = value } }
                )).font(.callout)

                Toggle("Skip when work is already busy", isOn: Binding(
                    get: { source.skipIfWorkBusy },
                    set: { value in model.updateSource(handle) { $0.skipIfWorkBusy = value } }
                )).font(.callout)

                picker("Shows as", selection: Binding(
                    get: { source.availability },
                    set: { value in model.updateSource(handle) { $0.availability = value } }
                ), options: Availability.allCases, label: \.rawValue)

                skippedDays(handle, source: source)

                Divider()

                // The one place a user is likely to assume the wrong thing:
                // these read the source event's title, and nothing about them
                // changes what a blocker is called (SPEC §7).
                Text("A title is only read to decide what to mirror. Blockers are still called what “Shown as” says.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                titleFilterEditor(.matches, source: handle, entries: source.titleMatches)
                titleFilterEditor(.excludes, source: handle, entries: source.titleExcludes)
            }
        }
    }

    /// Which work calendar this source's blockers go to.
    ///
    /// A popup for the same reason the account and calendar pickers are popups:
    /// a free-text typo in a calendar title hard-errors the whole sync (SPEC
    /// §11.1), and a popup cannot be wrong. Empty means the target calendar, so
    /// that is a row rather than a blank.
    @ViewBuilder
    private func targetCalendarPicker(_ handle: SourceHandle, source: SourceConfig) -> some View {
        // Resolved in the TARGET account, not this source's account — that is
        // where blockers are written (SPEC §4.1).
        let targetAccount = model.editingConfig?.target.account ?? ""
        let inherited = model.editingConfig?.target.calendar ?? ""
        let calendars = model.writableCalendarChoices(inAccount: targetAccount)

        Picker("Write blockers to", selection: Binding(
            get: { source.targetCalendar },
            set: { value in model.updateSource(handle) { $0.targetCalendar = value } }
        )) {
            Text(SourceFieldRules.targetCalendarDescription(
                SourceFieldRules.inheritedTargetCalendar, inheriting: inherited
            ))
            .tag(SourceFieldRules.inheritedTargetCalendar)

            // A saved value naming a calendar that no longer exists stays in the
            // list, so the picker cannot silently rewrite config to something
            // the user never chose.
            if !source.targetCalendar.isEmpty, !calendars.contains(source.targetCalendar) {
                Text("\(source.targetCalendar) (not found)").tag(source.targetCalendar)
            }
            ForEach(calendars, id: \.self) { Text($0).tag($0) }
        }
        .font(.callout)
    }

    /// Days this source mirrors nothing on.
    ///
    /// Seven switches rather than a multi-select, so each day says what it is to
    /// a screen reader. The last remaining day refuses to turn on: skipping all
    /// seven mirrors nothing, and `ConfigLoader.validate` rejects it — better to
    /// stop the click than to explain the error it would have caused.
    private func skippedDays(_ handle: SourceHandle, source: SourceConfig) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Skip these days").font(.callout)
                Spacer()
                Text(SourceFieldRules.skippedDaysDescription(source.skipWeekdays) ?? "none")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                ForEach(Weekday.pickerOrder, id: \.self) { component in
                    let name = Weekday.name(for: component) ?? ""
                    let isSkipped = source.skipWeekdays.contains(component)
                    Toggle(name.capitalized, isOn: Binding(
                        get: { isSkipped },
                        set: { value in
                            model.updateSource(handle) { edited in
                                if value {
                                    edited.skipWeekdays.insert(component)
                                } else {
                                    edited.skipWeekdays.remove(component)
                                }
                            }
                        }
                    ))
                    .toggleStyle(.button)
                    .font(.caption)
                    .disabled(!SourceFieldRules.canSkip(component, given: source.skipWeekdays))
                    .accessibilityLabel("Skip \(name.capitalized)")
                }
            }

            // One day left, and it will not turn on.
            if source.skipWeekdays.count == Weekday.componentCount - 1 {
                Text(SourceFieldRules.lastDayRefusedNote)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One list per field, a row per entry — never a comma-joined text field,
    /// because a calendar title can contain a comma.
    ///
    /// Blank and duplicate entries are refused in front of the field rather
    /// than at save: `ConfigLoader.validate` throws on a blank one, and that
    /// error names a config key at a moment far away from the keystroke.
    private func titleFilterEditor(
        _ field: TitleFilterField,
        source handle: SourceHandle,
        entries: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.title).font(.callout)

            // Rows carry their own identity rather than their position: a
            // commit can arrive after its row moved, and by position it would
            // land on whatever shifted underneath — silently, since the index
            // is still in range.
            ForEach(model.titleFilterRows(field, of: handle)) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        TextField("", text: Binding(
                            get: { row.text },
                            set: { model.setTitleFilterEntry($0, field, of: handle, row: row.id) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Entry in the \(field.accessibilityName)")

                        Button {
                            model.removeTitleFilter(field, from: handle, row: row.id)
                        } label: {
                            Image(systemName: "minus")
                        }
                        .accessibilityLabel(removeLabel(for: row.text, in: field))
                    }
                    // Live, because a row can be emptied in place and the user
                    // should see why Save went away. `checkRow`, not `check`:
                    // an emptied row is an error, where an empty add field is
                    // just an add field nobody has typed into yet.
                    if let message = model.titleFilterRowMessage(field, of: handle, row: row.id) {
                        Text(message).font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 6) {
                TextField(field.addPlaceholder, text: Binding(
                    get: { model.titleFilterDraft(field, of: handle) },
                    set: { model.setTitleFilterDraft(field, to: $0, of: handle) }
                ))
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.addTitleFilter(field, to: handle) }

                Button {
                    model.addTitleFilter(field, to: handle)
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!isAddable(model.titleFilterDraftCheck(field, of: handle)))
                .accessibilityLabel("Add to the \(field.accessibilityName)")
            }

            if let message = TitleFilterEntry.message(
                for: model.titleFilterDraftCheck(field, of: handle)
            ) {
                Text(message).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if entries.isEmpty {
                Text(field.emptyMeaning).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Names the entry as well as its list, so a screen reader user knows which
    /// row's remove button they are on, not just which list.
    private func removeLabel(for text: String, in field: TitleFilterField) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? "Remove the empty entry from the \(field.accessibilityName)"
            : "Remove “\(trimmed)” from the \(field.accessibilityName)"
    }

    private func isAddable(_ check: TitleFilterEntry.Check) -> Bool {
        if case .valid = check {
            return true
        }
        return false
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if let message = SettingsMessagePolicy.footerMessage(
                validationProblem: model.settingsProblem,
                saveError: model.saveError
            ) {
                Text(message)
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
                .disabled(model.editingConfig == nil || model.settingsProblem != nil)
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
