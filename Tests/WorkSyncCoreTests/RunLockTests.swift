import XCTest
@testable import WorkSyncCore

final class RunLockTests: XCTestCase {
    private var path: String!

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "worksync-test-\(UUID().uuidString).lock"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: path)
        super.tearDown()
    }

    func testSecondAcquisitionInSameProcessIsRefused() {
        let first = RunLock(path: path)
        XCTAssertNotNil(first)
        // flock is per open file description, so a second open() in this
        // process contends exactly as another process would.
        XCTAssertNil(RunLock(path: path), "a held lock must refuse, not queue")
        first?.unlock()
    }

    func testLockIsReacquirableAfterUnlock() {
        let first = RunLock(path: path)
        XCTAssertNotNil(first)
        first?.unlock()

        let second = RunLock(path: path)
        XCTAssertNotNil(second, "releasing must actually release")
        second?.unlock()
    }

    func testUnlockIsIdempotent() {
        let lock = RunLock(path: path)
        lock?.unlock()
        lock?.unlock() // must not close an unrelated descriptor
        XCTAssertNotNil(RunLock(path: path))
    }

    func testCreatesTheParentDirectory() {
        let nested = NSTemporaryDirectory() + "worksync-test-\(UUID().uuidString)/nested/.lock"
        defer {
            try? FileManager.default.removeItem(
                atPath: (((nested as NSString).deletingLastPathComponent) as NSString).deletingLastPathComponent
            )
        }
        let lock = RunLock(path: nested)
        XCTAssertNotNil(lock, "a first run on a clean machine has no ~/.config/worksync yet")
        lock?.unlock()
    }
}
