import XCTest
@testable import WorkSyncCore

final class MarkerTests: XCTestCase {
    func testURLStringRoundTrip() {
        let marker = Marker(sourceID: "personal", key: "abc123def4567890")
        XCTAssertEqual(marker.urlString, "worksync://v1/personal/abc123def4567890")
        XCTAssertEqual(Marker.parse(marker.urlString), marker)
    }

    func testKeyIsStableAndDistinct() {
        let d1 = Date(timeIntervalSince1970: 1_000_000)
        let d2 = Date(timeIntervalSince1970: 2_000_000)
        let k1 = Marker.key(externalIdentifier: "EXT-1", occurrenceDate: d1)
        XCTAssertEqual(k1, Marker.key(externalIdentifier: "EXT-1", occurrenceDate: d1), "deterministic")
        XCTAssertEqual(k1.count, 16)
        XCTAssertNotEqual(
            k1,
            Marker.key(externalIdentifier: "EXT-1", occurrenceDate: d2),
            "same series, different occurrence → different key"
        )
        XCTAssertNotEqual(k1, Marker.key(externalIdentifier: "EXT-2", occurrenceDate: d1))
    }

    func testCoalescedKeyOrderIndependent() {
        let d1 = Date(timeIntervalSince1970: 1000)
        let d2 = Date(timeIntervalSince1970: 2000)
        let a = Marker.coalescedKey(constituents: [("X", d1), ("Y", d2)])
        let b = Marker.coalescedKey(constituents: [("Y", d2), ("X", d1)])
        XCTAssertEqual(a, b, "constituent order must not change the key")
        XCTAssertNotEqual(
            a,
            Marker.coalescedKey(constituents: [("X", d1)]),
            "gaining/losing a constituent produces a new key"
        )
    }

    func testExtractPrefersNotesThenURL() {
        let notesMarker = Marker(sourceID: "a", key: "1111111111111111")
        let urlMarker = Marker(sourceID: "b", key: "2222222222222222")
        let notes = "\(Marker.notesHeaderLine)\n\(notesMarker.urlString)"

        XCTAssertEqual(
            Marker.extract(url: urlMarker.urlString, notes: notes),
            notesMarker,
            "notes last line is the primary location"
        )
        XCTAssertEqual(
            Marker.extract(url: urlMarker.urlString, notes: nil),
            urlMarker,
            "url is the fallback when notes are stripped"
        )
        XCTAssertEqual(
            Marker.extract(url: nil, notes: notes),
            notesMarker,
            "notes alone suffice when the backend drops the url field"
        )
    }

    func testExtractRejectsGarbage() {
        XCTAssertNil(Marker.extract(url: "https://example.com/meeting", notes: "Weekly staff sync"))
        XCTAssertNil(Marker.extract(url: nil, notes: nil))
        XCTAssertNil(Marker.parse("worksync://v1//missing-source"))
        XCTAssertNil(Marker.parse("worksync://nonsense"))
    }

    func testUnknownVersionParsedButNotCurrent() throws {
        let parsed = Marker.parse("worksync://v2/personal/deadbeefdeadbeef")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.version, 2)
        XCTAssertFalse(try XCTUnwrap(parsed?.isCurrentVersion), "only v1 markers may ever be mutated")
    }

    func testExtractToleratesUserEditedNotes() {
        let marker = Marker(sourceID: "personal", key: "abcdefabcdefabcd")
        let notes = "User wrote a comment here\n\n\(Marker.notesHeaderLine)\n  \(marker.urlString)  "
        XCTAssertEqual(Marker.extract(url: nil, notes: notes), marker)
    }
}
