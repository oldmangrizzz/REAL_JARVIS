import XCTest
@testable import JarvisCore

final class CommandRateLimiterTests: XCTestCase {
    func testConstructorDefaults() {
        let l = CommandRateLimiter()
        XCTAssertEqual(l.capacity, 5)
        XCTAssertEqual(l.window, 60, accuracy: 1e-9)
    }

    func testConstructorClampsCapacityLowerBound() {
        XCTAssertEqual(CommandRateLimiter(capacity: 0, window: 10).capacity, 1)
        XCTAssertEqual(CommandRateLimiter(capacity: -5, window: 10).capacity, 1)
    }

    func testConstructorClampsWindowLowerBound() {
        XCTAssertEqual(CommandRateLimiter(capacity: 3, window: 0).window, 0.1, accuracy: 1e-9)
        XCTAssertEqual(CommandRateLimiter(capacity: 3, window: -1).window, 0.1, accuracy: 1e-9)
    }

    func testAllowsUpToCapacity() {
        let l = CommandRateLimiter(capacity: 3, window: 10)
        let t = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(l.allow(now: t))
        XCTAssertTrue(l.allow(now: t))
        XCTAssertTrue(l.allow(now: t))
    }

    func testRefusesBeyondCapacityWithinWindow() {
        let l = CommandRateLimiter(capacity: 2, window: 10)
        let t = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(l.allow(now: t))
        XCTAssertTrue(l.allow(now: t.addingTimeInterval(1)))
        XCTAssertFalse(l.allow(now: t.addingTimeInterval(2)))
    }

    func testEvictsExpiredTimestamps() {
        let l = CommandRateLimiter(capacity: 2, window: 10)
        let t = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(l.allow(now: t))
        XCTAssertTrue(l.allow(now: t.addingTimeInterval(1)))
        XCTAssertFalse(l.allow(now: t.addingTimeInterval(5)))
        // Advance past window for first two stamps
        XCTAssertTrue(l.allow(now: t.addingTimeInterval(12)))
    }

    func testCutoffIsStrictlyLessThan() {
        // Entries at exactly cutoff are retained (removeAll where < cutoff only evicts strictly older).
        let l = CommandRateLimiter(capacity: 1, window: 10)
        let t = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(l.allow(now: t))
        // Exactly window seconds later: first stamp is at cutoff boundary (not < cutoff) → still counted.
        XCTAssertFalse(l.allow(now: t.addingTimeInterval(10)))
        // Just past the boundary: evicts the first stamp.
        XCTAssertTrue(l.allow(now: t.addingTimeInterval(10.0001)))
    }

    func testLimitExceededResponseCopy() {
        XCTAssertEqual(
            CommandRateLimiter.limitExceededResponse,
            "I'm receiving too many commands too quickly. Give me a moment."
        )
    }

    func testConcurrentAllowIsThreadSafe() {
        let l = CommandRateLimiter(capacity: 50, window: 10)
        let t = Date(timeIntervalSince1970: 2_000)
        let q = DispatchQueue(label: "crl.fanout", attributes: .concurrent)
        let group = DispatchGroup()
        let counter = NSLock()
        var allowed = 0
        for _ in 0..<200 {
            group.enter()
            q.async {
                let ok = l.allow(now: t)
                if ok {
                    counter.lock()
                    allowed += 1
                    counter.unlock()
                }
                group.leave()
            }
        }
        group.wait()
        XCTAssertEqual(allowed, 50, "capacity must be respected under concurrent contention")
    }
}
