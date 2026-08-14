import XCTest
@testable import WorkSyncCore

final class LoggerTests: XCTestCase {
    private var directory: String!

    override func setUp() {
        super.setUp()
        directory = NSTemporaryDirectory() + "worksync-log-\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: directory)
        super.tearDown()
    }

    private var logPath: String {
        directory + "/worksync.log"
    }

    private func contents(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    func testWritesAndCreatesTheDirectory() {
        Logger(directory: directory, level: .info).info("hello")
        XCTAssertTrue(contents(logPath).contains("hello"))
        XCTAssertTrue(contents(logPath).contains("[info]"))
    }

    func testLevelFiltering() {
        let logger = Logger(directory: directory, level: .warn)
        logger.error("shown-error")
        logger.warn("shown-warn")
        logger.info("hidden-info")
        logger.debug("hidden-debug")

        let text = contents(logPath)
        XCTAssertTrue(text.contains("shown-error"))
        XCTAssertTrue(text.contains("shown-warn"))
        XCTAssertFalse(text.contains("hidden-info"))
        XCTAssertFalse(text.contains("hidden-debug"))
    }

    func testDebugLevelAllowsEverything() {
        let logger = Logger(directory: directory, level: .debug)
        logger.error("e")
        logger.debug("d")
        let text = contents(logPath)
        XCTAssertTrue(text.contains("e") && text.contains("d"))
    }

    func testRotationKeepsBoundedHistory() {
        // A machine syncing every ten minutes for a year must not fill the disk.
        let logger = Logger(directory: directory, level: .info)
        let chunk = String(repeating: "x", count: 4096)
        for index in 0 ..< 400 {
            logger.info("\(index) \(chunk)")
        }

        let manager = FileManager.default
        XCTAssertTrue(manager.fileExists(atPath: logPath))

        // The live log plus at most archiveCount archives, and nothing beyond.
        var kept = 1
        for index in 1 ... Logger.archiveCount where manager.fileExists(atPath: "\(logPath).\(index)") {
            kept += 1
        }
        XCTAssertLessThanOrEqual(kept, Logger.archiveCount + 1)
        XCTAssertFalse(
            manager.fileExists(atPath: "\(logPath).\(Logger.archiveCount + 1)"),
            "the oldest archive must be dropped, not accumulated"
        )

        for index in 1 ... Logger.archiveCount {
            let path = "\(logPath).\(index)"
            guard manager.fileExists(atPath: path) else { continue }
            let size = (try? manager.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            XCTAssertLessThanOrEqual(size ?? 0, Logger.maxBytes + 8192)
        }
    }

    func testMostRecentLinesSurviveRotation() {
        let logger = Logger(directory: directory, level: .info)
        let chunk = String(repeating: "y", count: 4096)
        for index in 0 ..< 300 {
            logger.info("\(index) \(chunk)")
        }
        logger.info("FINAL-LINE")
        XCTAssertTrue(contents(logPath).contains("FINAL-LINE"), "the live log holds the newest entries")
    }

    // MARK: Timestamps

    /// Log timestamps are machine-readable, so they must not follow the user's
    /// calendar. An unconfigured DateFormatter inherits `Locale.current`, and
    /// the same instant then writes as 2569-… under a Thai system calendar or
    /// 0008-… under a Japanese one — which silently breaks sorting, parsing,
    /// and every "when did this run" question. Invisible on an en_US machine,
    /// which is exactly why it needs a test.
    func testTimestampsAreGregorianRegardlessOfTheSystemCalendar() {
        // Asserted on the formatter's configuration, not on its output: CI runs
        // under en_US, where the broken and fixed versions print identically.
        // Only a Thai or Japanese system calendar shows the difference, so the
        // pinning is the only thing a test here can actually hold on to.
        XCTAssertEqual(Logger.timestampFormatter.locale.identifier, "en_US_POSIX")
        XCTAssertEqual(Logger.timestampFormatter.calendar.identifier, .gregorian)

        // And the pinning does what it is for: the same instant renders the
        // same way it would for a user whose calendar is not Gregorian.
        let instant = Date(timeIntervalSince1970: 1_770_000_000)
        XCTAssertTrue(
            Logger.timestampFormatter.string(from: instant).hasPrefix("2026-"),
            "got \(Logger.timestampFormatter.string(from: instant))"
        )
    }

    func testTheTimestampFormatterIsBuiltOnceRatherThanPerLine() {
        // DateFormatter is among the most expensive objects in Foundation to
        // construct, and this used to happen on every single log line.
        XCTAssertTrue(Logger.timestampFormatter === Logger.timestampFormatter)
    }

    func testTimestampsUseAFixedSortableLayout() {
        // Sortable as plain text is the property that makes `sort` and `grep`
        // on the log file work at all.
        let logger = Logger(directory: directory, level: .info)
        logger.info("hello")

        let stamp = String(contents(logPath).prefix(19))
        XCTAssertEqual(
            stamp.count, 19,
            "expected yyyy-MM-dd HH:mm:ss, got \"\(stamp)\""
        )
        XCTAssertNotNil(
            try? Date("\(stamp.replacingOccurrences(of: " ", with: "T"))Z", strategy: .iso8601),
            "\"\(stamp)\" does not parse as an ISO-shaped timestamp"
        )
    }
}

final class LastRunTests: XCTestCase {
    private var path: String!

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "worksync-lastrun-\(UUID().uuidString)/last-run.json"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
        super.tearDown()
    }

    func testRoundTrip() {
        let run = LastRun(
            finishedAt: Date(timeIntervalSince1970: 1_700_000_000),
            succeeded: true,
            summary: "created=1 updated=0 deleted=0 skipped=0 unchanged=5"
        )
        XCTAssertTrue(LastRunStore.save(run, path: path))
        XCTAssertEqual(LastRunStore.load(path: path), run)
    }

    func testMissingFileReadsAsNil() {
        XCTAssertNil(LastRunStore.load(path: path))
    }

    func testCorruptFileReadsAsNilRatherThanThrowing() {
        // Display state must never be able to break a sync.
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? "not json".write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertNil(LastRunStore.load(path: path))
    }

    func testStalenessUsesTwiceTheInterval() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let run = LastRun(finishedAt: now, succeeded: true, summary: "")

        XCTAssertFalse(run.isStale(intervalMinutes: 10, now: now.addingTimeInterval(15 * 60)))
        XCTAssertTrue(run.isStale(intervalMinutes: 10, now: now.addingTimeInterval(25 * 60)))
    }
}

final class LastRunPathTests: XCTestCase {
    func testPathIsASiblingOfTheConfig() {
        XCTAssertEqual(
            LastRunStore.path(forConfigAt: "/etc/worksync/config.toml"),
            "/etc/worksync/last-run.json"
        )
    }

    func testTwoConfigsDoNotShareState() {
        // Running with --config against a second config must not show the
        // first one's history, or overwrite it.
        let a = LastRunStore.path(forConfigAt: "/tmp/a/config.toml")
        let b = LastRunStore.path(forConfigAt: "/tmp/b/config.toml")
        XCTAssertNotEqual(a, b)
    }

    func testDefaultConfigPathYieldsTheDefaultStatePath() {
        XCTAssertEqual(
            LastRunStore.path(forConfigAt: ConfigLoader.defaultPath),
            LastRunStore.defaultPath
        )
    }
}
