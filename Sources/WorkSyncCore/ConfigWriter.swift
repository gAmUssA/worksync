import Foundation

public enum ConfigWriteError: Error, LocalizedError, Equatable {
    case roundTripFailed(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .roundTripFailed(detail):
            "Refusing to write config: the result did not load back correctly (\(detail)). "
                + "Your existing config.toml is unchanged."
        case let .writeFailed(detail):
            "Could not write config: \(detail)"
        }
    }
}

/// How much of the user's original file survived a save.
///
/// Reported rather than inferred, because the two outcomes look identical from
/// the outside: the save succeeds and the values are right either way, but in
/// one of them every comment the user wrote is gone. Silently returning a file
/// stripped of its comments is the kind of loss that is only noticed much
/// later, when there is no undo left.
public enum ConfigWriteOutcome: Equatable {
    /// The normal path: only the changed lines were touched.
    case preserved
    /// The line edit did not round-trip, so the file was rewritten from
    /// scratch. Values are correct; comments and layout are lost.
    case reserialized

    public var warning: String? {
        switch self {
        case .preserved: nil
        case .reserialized:
            "Settings were saved, but the file had to be rewritten from scratch, "
                + "so comments and layout were lost. The previous file is at config.toml.bak."
        }
    }
}

/// Writes a `Config` back to disk without destroying the file a human wrote.
///
/// config.toml is hand-editable by definition (SPEC §2), so any programmatic
/// writer has to return a file the user still recognizes. Re-serializing
/// through TOMLKit would strip every comment and alphabetize the keys, so this
/// edits the original text line by line instead and only falls back to full
/// serialization when there is no original to preserve.
public enum ConfigWriter {
    // MARK: File-level

    /// Saves `config`, preserving the existing file's comments and layout.
    ///
    /// Refuses to write anything that does not load back cleanly: a writer that
    /// can hand the next sync pass an unparseable file is worse than one that
    /// refuses to run.
    @discardableResult
    public static func save(_ config: Config, to path: String) throws -> ConfigWriteOutcome {
        // Up front, so an invalid config reports what is actually wrong with it
        // ("Invalid source id …") instead of failing the round-trip check
        // further down and blaming the writer for refusing to reload its own
        // output. The file is protected either way; only the message differs.
        try ConfigLoader.validate(config)

        let original = try? String(contentsOfFile: path, encoding: .utf8)
        let previous = original.flatMap { try? ConfigLoader.parse($0) }

        let updated: String
        let outcome: ConfigWriteOutcome
        if let original, let previous {
            let edited = apply(config, previous: previous, to: original)
            // The self-check is on the produced text, not on our own diffing
            // logic, so a bug anywhere upstream still cannot corrupt the file.
            updated = try verified(edited, matches: config, fallback: config)
            outcome = updated == edited ? .preserved : .reserialized
        } else {
            // No usable original — a brand-new file, or one too broken to parse.
            // Comment loss is unavoidable here and expected (SPEC §4.3 step 6).
            updated = try verified(serialize(config), matches: config, fallback: nil)
            outcome = original == nil ? .preserved : .reserialized
        }

        if original != nil {
            // Backup before overwriting, so a bad write is always recoverable.
            try? FileManager.default.removeItem(atPath: path + ".bak")
            try? FileManager.default.copyItem(atPath: path, toPath: path + ".bak")
        }

        do {
            try FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try updated.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            throw ConfigWriteError.writeFailed(error.localizedDescription)
        }
        return outcome
    }

    /// Parses the produced text and compares it to what was intended.
    private static func verified(
        _ text: String,
        matches intended: Config,
        fallback: Config?
    ) throws -> String {
        if let parsed = try? ConfigLoader.parse(text), parsed == intended {
            return text
        }
        guard let fallback else {
            throw ConfigWriteError.roundTripFailed("serialized output did not reload as written")
        }
        // The line editor produced something wrong. Full serialization loses
        // comments but is simple enough to trust; it gets the same check.
        let serialized = serialize(fallback)
        guard let parsed = try? ConfigLoader.parse(serialized), parsed == fallback else {
            throw ConfigWriteError.roundTripFailed("neither the line edit nor a full rewrite reloaded correctly")
        }
        return serialized
    }

    // MARK: Line-level edit

    /// Applies `config` onto `original`, changing only the lines that need it.
    public static func apply(_ config: Config, previous: Config, to original: String) -> String {
        var document = TomlDocument(text: original)

        updateScalars(
            in: &document,
            header: "[general]",
            changes: generalChanges(from: previous.general, to: config.general)
        )
        updateScalars(
            in: &document,
            header: "[target]",
            changes: targetChanges(from: previous.target, to: config.target)
        )
        updateSources(in: &document, previous: previous.sources, new: config.sources)

        return document.text
    }

    private static func updateScalars(
        in document: inout TomlDocument,
        header: String,
        changes: [String: String]
    ) {
        guard !changes.isEmpty else { return }
        guard let index = document.sections.firstIndex(where: {
            $0.header?.trimmingCharacters(in: .whitespaces) == header
        }) else {
            // Section absent entirely: append it rather than dropping the edit.
            var section = TomlDocument.Section(leading: [""], header: header, body: [])
            for key in changes.keys.sorted() {
                TomlDocument.setValue(changes[key]!, forKey: key, in: &section)
            }
            document.sections.append(section)
            return
        }
        for key in changes.keys.sorted() {
            TomlDocument.setValue(changes[key]!, forKey: key, in: &document.sections[index])
        }
    }

    /// Matches `[[source]]` blocks by id, edits them in place, drops removed
    /// ones, appends new ones, and reorders to match the new config.
    ///
    /// Order is load-bearing rather than cosmetic — the first-listed source
    /// wins cross-source dedup (SPEC §4.1) — which is why reordering has to
    /// move real blocks of text rather than rewriting ids in place.
    private static func updateSources(
        in document: inout TomlDocument,
        previous: [SourceConfig],
        new: [SourceConfig]
    ) {
        let blockIndices = document.sections.indices.filter { document.sections[$0].isSourceBlock }
        guard !blockIndices.isEmpty || !new.isEmpty else { return }

        // Existing blocks keyed by the id they currently declare on disk.
        var blocksByID: [String: TomlDocument.Section] = [:]
        for index in blockIndices {
            let section = document.sections[index]
            if let raw = TomlDocument.value(forKey: "id", in: section) {
                blocksByID[unquote(raw)] = section
            }
        }
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })

        var rebuilt: [TomlDocument.Section] = []
        for source in new {
            if var existing = blocksByID[source.id] {
                let before = previousByID[source.id] ?? source
                for (key, value) in sourceChanges(from: before, to: source) {
                    TomlDocument.setValue(value, forKey: key, in: &existing)
                }
                rebuilt.append(existing)
            } else {
                rebuilt.append(synthesize(source))
            }
        }

        // Splice the rebuilt run back where the first block used to be; blocks
        // that vanished simply are not in `rebuilt`.
        var result: [TomlDocument.Section] = []
        var inserted = false
        for (index, section) in document.sections.enumerated() {
            if blockIndices.contains(index) {
                if !inserted {
                    result += rebuilt
                    inserted = true
                }
                continue
            }
            result.append(section)
        }
        if !inserted {
            result += rebuilt
        }
        document.sections = result
    }

    private static func synthesize(_ source: SourceConfig) -> TomlDocument.Section {
        var section = TomlDocument.Section(leading: [""], header: "[[source]]", body: [])
        let defaults = SourceConfig(id: source.id, account: source.account, calendar: source.calendar)
        // Always write identity; write everything else only where it differs
        // from the default, so a new block stays readable.
        var lines = [
            "id = \(TomlValue.string(source.id))",
            "account = \(TomlValue.string(source.account))",
            "calendar = \(TomlValue.string(source.calendar))",
        ]
        for (key, value) in sourceChanges(from: defaults, to: source).sorted(by: { $0.key < $1.key })
            where !["id", "account", "calendar"].contains(key) {
            lines.append("\(key) = \(value)")
        }
        section.body = lines
        return section
    }

    private static func unquote(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    // MARK: Field diffs

    private static func generalChanges(from old: GeneralConfig, to new: GeneralConfig) -> [String: String] {
        var changes: [String: String] = [:]
        if old.windowDays != new.windowDays {
            changes["window_days"] = TomlValue.int(new.windowDays)
        }
        if old.intervalMinutes != new
            .intervalMinutes {
            changes["interval_minutes"] = TomlValue.int(new.intervalMinutes)
        }
        if old.timezone != new.timezone {
            changes["timezone"] = TomlValue.string(new.timezone)
        }
        if old.logLevel != new.logLevel {
            changes["log_level"] = TomlValue.string(new.logLevel.rawValue)
        }
        if old.notify != new.notify {
            changes["notify"] = TomlValue.string(new.notify.rawValue)
        }
        if old.changeDriven != new.changeDriven {
            changes["change_driven"] = TomlValue.bool(new.changeDriven)
        }
        if old.changeDebounceSeconds != new.changeDebounceSeconds {
            changes["change_debounce_seconds"] = TomlValue.int(new.changeDebounceSeconds)
        }
        return changes
    }

    private static func targetChanges(from old: TargetConfig, to new: TargetConfig) -> [String: String] {
        var changes: [String: String] = [:]
        if old.account != new.account {
            changes["account"] = TomlValue.string(new.account)
        }
        if old.calendar != new.calendar {
            changes["calendar"] = TomlValue.string(new.calendar)
        }
        return changes
    }

    private static func sourceChanges(from old: SourceConfig, to new: SourceConfig) -> [String: String] {
        var changes: [String: String] = [:]
        if old.id != new.id {
            changes["id"] = TomlValue.string(new.id)
        }
        if old.account != new.account {
            changes["account"] = TomlValue.string(new.account)
        }
        if old.calendar != new.calendar {
            changes["calendar"] = TomlValue.string(new.calendar)
        }
        if old.titleTemplate != new.titleTemplate {
            changes["title_template"] = TomlValue.string(new.titleTemplate)
        }
        if old.targetCalendar != new
            .targetCalendar {
            changes["target_calendar"] = TomlValue.string(new.targetCalendar)
        }
        if old.coalesce != new.coalesce {
            changes["coalesce"] = TomlValue.bool(new.coalesce)
        }
        if old.coalesceGapMinutes != new.coalesceGapMinutes {
            changes["coalesce_gap_minutes"] = TomlValue.int(new.coalesceGapMinutes)
        }
        if old.minDurationMinutes != new.minDurationMinutes {
            changes["min_duration_minutes"] = TomlValue.int(new.minDurationMinutes)
        }
        if old.maxDurationMinutes != new.maxDurationMinutes {
            changes["max_duration_minutes"] = TomlValue.int(new.maxDurationMinutes)
        }
        if old.paddingBeforeMinutes != new.paddingBeforeMinutes {
            changes["padding_before_minutes"] = TomlValue.int(new.paddingBeforeMinutes)
        }
        if old.paddingAfterMinutes != new.paddingAfterMinutes {
            changes["padding_after_minutes"] = TomlValue.int(new.paddingAfterMinutes)
        }
        if old.skipWeekdays != new.skipWeekdays {
            changes["skip_weekdays"] = TomlValue.weekdays(new.skipWeekdays)
        }
        if old.includeAllDay != new.includeAllDay {
            changes["include_all_day"] = TomlValue.bool(new.includeAllDay)
        }
        if old.skipIfWorkBusy != new
            .skipIfWorkBusy {
            changes["skip_if_work_busy"] = TomlValue.bool(new.skipIfWorkBusy)
        }
        if old.availability != new
            .availability {
            changes["availability"] = TomlValue.string(new.availability.rawValue)
        }
        return changes
    }

    // MARK: Full serialization (fallback only)

    /// Used only for a brand-new file, or when the line edit fails its own
    /// self-check. Loses comments by construction, which is why it is not the
    /// normal path.
    public static func serialize(_ config: Config) -> String {
        var lines = [
            "[general]",
            "window_days = \(config.general.windowDays)",
            "interval_minutes = \(config.general.intervalMinutes)",
            "timezone = \(TomlValue.string(config.general.timezone))",
            "log_level = \(TomlValue.string(config.general.logLevel.rawValue))",
            "notify = \(TomlValue.string(config.general.notify.rawValue))",
            "change_driven = \(TomlValue.bool(config.general.changeDriven))",
            "change_debounce_seconds = \(config.general.changeDebounceSeconds)",
            "",
            "[target]",
            "account = \(TomlValue.string(config.target.account))",
            "calendar = \(TomlValue.string(config.target.calendar))",
        ]
        for source in config.sources {
            lines += [
                "",
                "[[source]]",
                "id = \(TomlValue.string(source.id))",
                "account = \(TomlValue.string(source.account))",
                "calendar = \(TomlValue.string(source.calendar))",
                "title_template = \(TomlValue.string(source.titleTemplate))",
                "target_calendar = \(TomlValue.string(source.targetCalendar))",
                "coalesce = \(TomlValue.bool(source.coalesce))",
                "coalesce_gap_minutes = \(source.coalesceGapMinutes)",
                "min_duration_minutes = \(source.minDurationMinutes)",
                "max_duration_minutes = \(source.maxDurationMinutes)",
                "padding_before_minutes = \(source.paddingBeforeMinutes)",
                "padding_after_minutes = \(source.paddingAfterMinutes)",
                "skip_weekdays = \(TomlValue.weekdays(source.skipWeekdays))",
                "include_all_day = \(TomlValue.bool(source.includeAllDay))",
                "skip_if_work_busy = \(TomlValue.bool(source.skipIfWorkBusy))",
                "availability = \(TomlValue.string(source.availability.rawValue))",
            ]
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
