import CryptoKit
import Foundation

/// The worksync marker identifies an event as managed and encodes its identity.
///
/// Format: worksync://v1/<source_id>/<key>
///
/// The notes last-line copy is the PRIMARY location — Google CalDAV and Exchange
/// drop the whole url field — and the url copy is supplementary (SPEC §7).
public struct Marker: Hashable, Sendable {
    public static let scheme = "worksync"
    public static let currentVersion = 1
    public static let notesHeaderLine = "Managed by worksync — do not edit; changes will be overwritten."

    public let version: Int
    public let sourceID: String
    public let key: String

    public init(sourceID: String, key: String) {
        version = Self.currentVersion
        self.sourceID = sourceID
        self.key = key
    }

    init(version: Int, sourceID: String, key: String) {
        self.version = version
        self.sourceID = sourceID
        self.key = key
    }

    public var isCurrentVersion: Bool {
        version == Self.currentVersion
    }

    /// worksync://v1/<source_id>/<key>
    public var urlString: String {
        "\(Self.scheme)://v\(version)/\(sourceID)/\(key)"
    }

    /// Notes body written to every managed event: header line + marker line.
    public var notesBlock: String {
        "\(Self.notesHeaderLine)\n\(urlString)"
    }

    // MARK: Key generation

    /// Key for a single (non-coalesced) source event: SHA-256 (first 16 hex chars)
    /// of externalIdentifier + occurrenceDate. occurrenceDate — NOT the current
    /// start date — so a moved detached occurrence keeps its identity (SPEC §5/§7).
    public static func key(externalIdentifier: String, occurrenceDate: Date) -> String {
        hash("\(externalIdentifier)|\(timestamp(occurrenceDate))")
    }

    /// Key for a coalesced block: hash of the sorted constituent identities.
    public static func coalescedKey(constituents: [(externalIdentifier: String, occurrenceDate: Date)]) -> String {
        let parts = constituents
            .map { "\($0.externalIdentifier)|\(timestamp($0.occurrenceDate))" }
            .sorted()
        return hash(parts.joined(separator: ";"))
    }

    private static func timestamp(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970.rounded()))
    }

    private static func hash(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).lowercased()
    }

    // MARK: Parsing

    /// Parses a marker string of any version. Returns nil for non-marker text.
    public static func parse(_ text: String) -> Marker? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("\(scheme)://") else { return nil }
        let rest = trimmed.dropFirst("\(scheme)://".count)
        let parts = rest.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard parts[0].hasPrefix("v"), let version = Int(parts[0].dropFirst()) else { return nil }
        let sourceID = String(parts[1])
        let key = String(parts[2])
        guard !sourceID.isEmpty, !key.isEmpty else { return nil }
        return Marker(version: version, sourceID: sourceID, key: key)
    }

    /// Extracts a marker from an event's fields. Checks the last non-empty line of
    /// notes first (primary), then the url field (supplementary). Both locations
    /// must be checked: an event written on one backend may come back with only
    /// one of them intact (SPEC §7).
    public static func extract(url: String?, notes: String?) -> Marker? {
        if let notes {
            let lines = notes.split(separator: "\n", omittingEmptySubsequences: true)
            if let last = lines.last, let marker = parse(String(last)) {
                return marker
            }
        }
        if let url, let marker = parse(url) {
            return marker
        }
        return nil
    }
}
