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

    // MARK: - Additional coverage

    func testRefusedCallDoesNotConsumeToken() {
        // A denied allow() must not append a timestamp, otherwise we'd poison future windows.
        let l = CommandRateLimiter(capacity: 2, window: 10)
        let t = Date(timeIntervalSince1970: 3_000)
        XCTAssertTrue(l.allow(now: t))
        XCTAssertTrue(l.allow(now: t.addingTimeInterval(1)))
        // Ten denials should not push the recovery time past the original two stamps.
        for i in 0..<10 { XCTAssertFalse(l.allow(now: t.addingTimeInterval(2 + Double(i) * 0.1))) }
        // After the window elapses relative to the first stamp only, exactly one slot frees up.
        XCTAssertTrue(l.allow(now: t.addingTimeInterval(10.0001)))
        XCTAssertFalse(l.allow(now: t.addingTimeInterval(10.0002)))
    }

    func testSlidingWindowEvictsStampByStamp() {
        let l = CommandRateLimiter(capacity: 3, window: 10)
        let t = Date(timeIntervalSince1970: 4_000)
        XCTAssertTrue(l.allow(now: t))                          // stamp @ 0
        XCTAssertTrue(l.allow(now: t.addingTimeInterval(3)))    // stamp @ 3
        XCTAssertTrue(l.allow(now: t.addingTimeInterval(6)))    // stamp @ 6, full
        XCTAssertFalse(l.allow(now: t.addingTimeInterval(7)))
        // At t+10.0001 the @0 stamp falls off; one slot frees.
        XCTAssertTrue(l.allow(now: t.addingTimeInterval(10.0001)))
        XCTAssertFalse(l.allow(now: t.addingTimeInterval(10.1)))
        // At t+13.0001 the @3 stamp falls off; one more slot frees.
        XCTAssertTrue(l.allow(now: t.addingTimeInterval(13.0001)))
    }

    func testRecoveryAfterFullWindow() {
        let l = CommandRateLimiter(capacity: 2, window: 5)
        let t = Date(timeIntervalSince1970: 5_000)
        XCTAssertTrue(l.allow(now: t))
        XCTAssertTrue(l.allow(now: t))
        XCTAssertFalse(l.allow(now: t))
        // Well past the window: full capacity restored.
        let later = t.addingTimeInterval(100)
        XCTAssertTrue(l.allow(now: later))
        XCTAssertTrue(l.allow(now: later))
        XCTAssertFalse(l.allow(now: later))
    }

    func testCapacityOneRhythm() {
        let l = CommandRateLimiter(capacity: 1, window: 2)
        let t = Date(timeIntervalSince1970: 6_000)
        XCTAssertTrue(l.allow(now: t))
        XCTAssertFalse(l.allow(now: t.addingTimeInterval(1)))
        XCTAssertTrue(l.allow(now: t.addingTimeInterval(2.0001)))
        XCTAssertFalse(l.allow(now: t.addingTimeInterval(3)))
        XCTAssertTrue(l.allow(now: t.addingTimeInterval(4.0002)))
    }

    func testMinimumWindowClampTakesEffect() {
        // window clamped to 0.1; confirm eviction happens at 0.1-second scale.
        let l = CommandRateLimiter(capacity: 1, window: -99)
        XCTAssertEqual(l.window, 0.1, accuracy: 1e-9)
        let t = Date(timeIntervalSince1970: 7_000)
        XCTAssertTrue(l.allow(now: t))
        XCTAssertFalse(l.allow(now: t.addingTimeInterval(0.05)))
        XCTAssertTrue(l.allow(now: t.addingTimeInterval(0.2)))
    }

    func testClockRewindDoesNotGrantExtraTokens() {
        // If the caller supplies an older `now`, the existing stamps remain in the future
        // relative to the cutoff and must still count toward capacity.
        let l = CommandRateLimiter(capacity: 2, window: 10)
        let t = Date(timeIntervalSince1970: 8_000)
        XCTAssertTrue(l.allow(now: t))
        XCTAssertTrue(l.allow(now: t.addingTimeInterval(1)))
        // Rewind clock by 5s — stamps are at t and t+1, cutoff is t-15 → still all in window.
        XCTAssertFalse(l.allow(now: t.addingTimeInterval(-5)))
    }

    func testDefaultNowParameterSmokes() {
        // Exercise the `now: Date = Date()` default to cover the default-argument path.
        let l = CommandRateLimiter(capacity: 1, window: 60)
        XCTAssertTrue(l.allow())
        XCTAssertFalse(l.allow())
    }
}
