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

    func testSecondAcquisitionInSameProcessIsRefused() throws {
        let first = try RunLock.acquire(path: path)
        XCTAssertNotNil(first)
        // flock is per open file description, so a second open() in this
        // process contends exactly as another process would.
        XCTAssertNil(try RunLock.acquire(path: path), "a held lock must refuse, not queue")
        first?.unlock()
    }

    func testLockIsReacquirableAfterUnlock() throws {
        let first = try RunLock.acquire(path: path)
        XCTAssertNotNil(first)
        first?.unlock()

        let second = try RunLock.acquire(path: path)
        XCTAssertNotNil(second, "releasing must actually release")
        second?.unlock()
    }

    func testUnlockIsIdempotent() throws {
        let lock = try RunLock.acquire(path: path)
        lock?.unlock()
        lock?.unlock() // must not close an unrelated descriptor
        XCTAssertNotNil(try RunLock.acquire(path: path))
    }

    func testCreatesTheParentDirectory() throws {
        let root = NSTemporaryDirectory() + "worksync-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        let lock = try RunLock.acquire(path: root + "/nested/.lock")
        XCTAssertNotNil(lock, "a first run on a clean machine has no ~/.config/worksync yet")
        lock?.unlock()
    }

    // MARK: Contention vs. a broken environment

    func testUnopenableLockPathThrowsRatherThanReadingAsContention() {
        // The distinction that matters: if this returned nil like contention
        // does, every sync would exit 0 having silently done nothing, forever,
        // and the logs would look healthy.
        let blocker = NSTemporaryDirectory() + "worksync-test-\(UUID().uuidString)"
        FileManager.default.createFile(atPath: blocker, contents: Data())
        defer { try? FileManager.default.removeItem(atPath: blocker) }

        // A path *through* a regular file can never be opened (ENOTDIR).
        XCTAssertThrowsError(try RunLock.acquire(path: blocker + "/nested/.lock")) { error in
            guard case .unavailable = error as? RunLockError else {
                return XCTFail("expected RunLockError.unavailable, got \(error)")
            }
        }
    }

    func testLockSetupFailureIsARerunnablePartialFailure() {
        // Not a config error: sending the user to edit config.toml would be wrong.
        XCTAssertEqual(ExitCodes.code(for: RunLockError.unavailable(path: "/x", code: ENOTDIR)), 3)
    }
}
