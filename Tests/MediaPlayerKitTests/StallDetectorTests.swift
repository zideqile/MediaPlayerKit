import XCTest
@testable import MediaPlayerKit

final class StallDetectorTests: XCTestCase {
    private func policy() -> StalledSourceSwitchPolicy {
        let p = StalledSourceSwitchPolicy(); p.enable = true; return p
    }
    func testCountThresholdChecksOnNextWaitingAndFiresOnce() {
        var detector = StallDetector()
        let p = policy()
        for n in 0..<4 {
            let time = Double(n)
            XCTAssertNil(detector.update(state: .buffering, at: time, isLive: true, allowed: true, policy: p))
            XCTAssertNil(detector.update(state: .buffering, at: time + 0.1, isLive: true, allowed: true, policy: p))
            XCTAssertNil(detector.update(state: .playing, at: time + 0.5, isLive: true, allowed: true, policy: p))
        }
        let result = detector.update(state: .buffering, at: 4, isLive: true, allowed: true, policy: p)
        XCTAssertEqual(result?["stalledCountInSlidingWindowInMs"] as? Int, 4)
        XCTAssertEqual(result?["stalledDurationInMsInSlidingWindowInMs"] as? Double, 2000)
        XCTAssertNil(detector.update(state: .buffering, at: 5, isLive: true, allowed: true, policy: p))
    }
    func testDurationBoundaryExpiryAndMinimum() {
        var d = StallDetector(); let p = policy()
        _ = d.update(state: .buffering, at: 0, isLive: true, allowed: true, policy: p)
        _ = d.update(state: .playing, at: 6, isLive: true, allowed: true, policy: p)
        XCTAssertNil(d.update(state: .buffering, at: 7, isLive: true, allowed: true, policy: p)) // exactly 6s
        _ = d.update(state: .playing, at: 7.1, isLive: true, allowed: true, policy: p) // ignored
        XCTAssertNil(d.update(state: .buffering, at: 8, isLive: true, allowed: true, policy: p))
        _ = d.update(state: .playing, at: 8.25, isLive: true, allowed: true, policy: p)
        XCTAssertEqual(d.update(state: .buffering, at: 9, isLive: true, allowed: true, policy: p)?["totalStalledCount"] as? Int, 2)
        d.reset()
        _ = d.update(state: .buffering, at: 0, isLive: true, allowed: true, policy: p)
        _ = d.update(state: .playing, at: 7, isLive: true, allowed: true, policy: p)
        XCTAssertNil(d.update(state: .buffering, at: 68, isLive: true, allowed: true, policy: p))
    }
    func testDisabledVODAndSuspensionDoNotGenerateStalls() {
        var d = StallDetector(); let p = policy()
        for live in [false, true] {
            p.enable = !live // one disabled, one VOD
            _ = d.update(state: .buffering, at: 0, isLive: live, allowed: true, policy: p)
            _ = d.update(state: .playing, at: 10, isLive: live, allowed: true, policy: p)
            XCTAssertNil(d.update(state: .buffering, at: 11, isLive: live, allowed: true, policy: p))
        }
        p.enable = true
        _ = d.update(state: .buffering, at: 12, isLive: true, allowed: true, policy: p)
        _ = d.update(state: .buffering, at: 13, isLive: true, allowed: false, policy: p)
        _ = d.update(state: .playing, at: 100, isLive: true, allowed: true, policy: p)
        XCTAssertNil(d.update(state: .buffering, at: 101, isLive: true, allowed: true, policy: p))
    }
    func testConfigurationAndRecovery() throws {
        let config = try JSONDecoder().decode(VPlayerConfig.self, from: Data("{\"stalledSourceSwitchPolicy\":{\"enable\":true}}".utf8))
        XCTAssertTrue(config.stalledSourceSwitchPolicy.enable)
        XCTAssertEqual(config.stalledSourceSwitchPolicy.slidingWindowInMs, 60000)
        XCTAssertFalse(VPlayerConfig().stalledSourceSwitchPolicy.enable)
        let error = NSError(domain: "MediaPlayerKit.Stall", code: 1)
        XCTAssertEqual(PlaybackErrorClassifier.classify(error), .stalled)
        XCTAssertEqual(PlaybackRecoveryPolicy.action(for: .stalled, hasNextEngine: true, hasNextSource: true), .nextSource)
        XCTAssertEqual(PlaybackRecoveryPolicy.action(for: .stalled, hasNextEngine: true, hasNextSource: false), .stop)
    }
}
