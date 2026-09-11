import Foundation

/// A TOML file kept as text, so edits can preserve everything a parser throws
/// away.
///
/// TOMLKit (and toml++ beneath it) discards comments at parse time and
/// reorders keys alphabetically on output, so the obvious load-edit-save round
/// trip would strip every comment and reflow the document (SPEC §4.3). This
/// type never reparses for writing: it locates the line that holds a value and
/// rewrites only that line.
struct TomlDocument {
    /// One `[header]` and the lines beneath it. The first section may have no
    /// header — the file preamble.
    struct Section {
        /// Comment and blank lines immediately above the header. They describe
        /// the block that follows, so they travel with it when blocks move.
        var leading: [String]
        var header: String?
        var body: [String]

        var isSourceBlock: Bool {
            header?.trimmingCharacters(in: .whitespaces) == "[[source]]"
        }

        var text: String {
            (leading + [header].compactMap { $0 } + body).joined(separator: "\n")
        }
    }

    var sections: [Section]
    /// Whether the original text ended with a newline, so writing back does not
    /// silently add or drop one.
    let hadTrailingNewline: Bool

    init(text: String) {
        hadTrailingNewline = text.hasSuffix("\n")
        var lines = text.components(separatedBy: "\n")
        if hadTrailingNewline, lines.last == "" {
            lines.removeLast()
        }

        var sections: [Section] = []
        var current = Section(leading: [], header: nil, body: [])

        for line in lines {
            if Self.isHeader(line) {
                // Comments and blanks directly above a header belong to it.
                var leading: [String] = []
                while let last = current.body.last, Self.isCommentOrBlank(last) {
                    leading.insert(current.body.removeLast(), at: 0)
                }
                if current.header != nil || !current.body.isEmpty || !current.leading.isEmpty {
                    sections.append(current)
                }
                current = Section(leading: leading, header: line, body: [])
            } else {
                current.body.append(line)
            }
        }
        sections.append(current)
        self.sections = sections
    }

    var text: String {
        let joined = sections.map(\.text).joined(separator: "\n")
        return hadTrailingNewline ? joined + "\n" : joined
    }

    // MARK: Line-level editing

    /// Rewrites `key`'s value inside `section`, keeping any trailing comment on
    /// the line that ends the value. Appends the key if it is not present.
    ///
    /// A hand-wrapped array spans several lines, so the whole span is replaced.
    /// Rewriting only the line the key sits on would leave the continuation
    /// lines orphaned and the file unparseable, which costs the user every
    /// comment in it when `ConfigWriter` falls back to full serialization.
    static func setValue(_ value: String, forKey key: String, in section: inout Section) {
        for index in section.body.indices {
            guard keyOnLine(section.body[index]) == key else { continue }
            let indent = section.body[index].prefix { $0 == " " || $0 == "\t" }
            if let end = arrayEnd(startingAt: index, in: section.body) {
                // The comment kept is the one after the closing bracket, where
                // a wrapped array's explanation conventionally sits. Comments
                // on the opening line or between the elements describe the old
                // elements, which are the thing being replaced.
                let comment = scan(section.body[end]).comment
                section.body.replaceSubrange(index ... end, with: ["\(indent)\(key) = \(value)\(comment)"])
            } else {
                let (_, comment) = splitValueAndComment(section.body[index])
                section.body[index] = "\(indent)\(key) = \(value)\(comment)"
            }
            return
        }
        // Not present: append after the last non-blank line so the key does not
        // land after the section's trailing blank lines.
        var insertAt = section.body.count
        while insertAt > 0, section.body[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            insertAt -= 1
        }
        section.body.insert("\(key) = \(value)", at: insertAt)
    }

    /// The index of the line closing an array that opens on `index` without
    /// closing there, or nil when the value ends on its own line.
    ///
    /// Only bracket depth is tracked. Inline tables and nested arrays are not
    /// in the config schema's vocabulary (SPEC §2), so nothing here tries to
    /// understand them beyond keeping the brackets balanced.
    static func arrayEnd(startingAt index: Int, in body: [String]) -> Int? {
        let line = body[index]
        guard let equals = line.firstIndex(of: "=") else { return nil }
        var depth = scan(String(line[line.index(after: equals)...])).depth
        guard depth > 0 else { return nil }

        var cursor = index + 1
        while cursor < body.count {
            depth += scan(body[cursor]).depth
            if depth <= 0 {
                return cursor
            }
            cursor += 1
        }
        // No closing bracket anywhere: the file is already broken. Leave the
        // span alone rather than swallowing the rest of the section.
        return nil
    }

    /// How much `text` changes the bracket depth before its trailing comment,
    /// and that comment. Brackets and `#` inside a quoted string do not count.
    private static func scan(_ text: String) -> (depth: Int, comment: String) {
        var depth = 0
        var inString = false
        var escaped = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\", inString {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                switch character {
                case "#": return (depth, String(text[index...]))
                case "[": depth += 1
                case "]": depth -= 1
                default: break
                }
            }
            index = text.index(after: index)
        }
        return (depth, "")
    }

    static func value(forKey key: String, in section: Section) -> String? {
        for line in section.body where keyOnLine(line) == key {
            return splitValueAndComment(line).value.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// The bare key on a `key = value` line, or nil for comments and blanks.
    static func keyOnLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        guard let equals = trimmed.firstIndex(of: "=") else { return nil }
        return String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces)
    }

    /// Splits a line at its trailing comment, ignoring `#` inside quotes — a
    /// title template of `"Busy #1"` must not be truncated.
    static func splitValueAndComment(_ line: String) -> (value: String, comment: String) {
        guard let equals = line.firstIndex(of: "=") else { return (line, "") }
        let after = line.index(after: equals)

        var inString = false
        var escaped = false
        var index = after
        while index < line.endIndex {
            let character = line[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if character == "#", !inString {
                return (String(line[after ..< index]), String(line[index...]))
            }
            index = line.index(after: index)
        }
        return (String(line[after...]), "")
    }

    private static func isHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
    }

    private static func isCommentOrBlank(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.hasPrefix("#")
    }
}

/// Rendering Swift values as TOML literals.
enum TomlValue {
    /// A TOML basic string. Control characters get their escape sequence —
    /// emitting one literally produces a file TOML cannot parse, which turns a
    /// save into a round-trip failure rather than a written config.
    ///
    /// Iterates unicode scalars, not characters: Swift treats CR LF as ONE
    /// grapheme cluster, so a `Character` switch matches neither "\r" nor "\n"
    /// and a Windows line ending would escape nothing. Only C0 and DEL need
    /// escaping — TOML permits C1 (U+0080–U+009F) literally.
    static func string(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\u{08}": escaped += "\\b"
            case "\t": escaped += "\\t"
            case "\n": escaped += "\\n"
            case "\u{0C}": escaped += "\\f"
            case "\r": escaped += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    escaped += String(format: "\\u%04X", scalar.value)
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }
        return "\"\(escaped)\""
    }

    static func int(_ value: Int) -> String {
        String(value)
    }

    static func bool(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    static func strings(_ values: [String]) -> String {
        "[" + values.map(string).joined(separator: ", ") + "]"
    }

    static func weekdays(_ components: Set<Int>) -> String {
        let names = Weekday.sortedForWriting(components).compactMap(Weekday.name(for:))
        return "[" + names.map(string).joined(separator: ", ") + "]"
    }
}
