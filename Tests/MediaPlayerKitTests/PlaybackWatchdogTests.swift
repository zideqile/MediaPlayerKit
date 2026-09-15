import XCTest
@testable import MediaPlayerKit

final class PlaybackWatchdogTests: XCTestCase {
    func testStartupDeadlineDoesNotResetWithRepeatedPreparingOrEarlyPlaying() {
        var watch = PlaybackWatchdog()
        XCTAssertNil(watch.check(at: 0, state: .preparing, enabled: true, startupMs: 15000, bufferingMs: 10000))
        XCTAssertNil(watch.check(at: 14, state: .playing, enabled: true, startupMs: 15000, bufferingMs: 10000))
        XCTAssertEqual(watch.check(at: 15, state: .playing, enabled: true, startupMs: 15000, bufferingMs: 10000), .startup)
        XCTAssertNil(watch.check(at: 30, state: .buffering, enabled: true, startupMs: 15000, bufferingMs: 10000))
        XCTAssertEqual(PlaybackRecoveryPolicy.action(for: .timeout, hasNextEngine: true, hasNextSource: true), .nextEngine)
        XCTAssertEqual(PlaybackRecoveryPolicy.action(for: .timeout, hasNextEngine: false, hasNextSource: true), .nextSource)
        XCTAssertEqual(PlaybackRecoveryPolicy.action(for: .timeout, hasNextEngine: false, hasNextSource: false), .stop)
    }
    func testBufferingClearsOnPlaybackAndPausedTimeDoesNotCount() {
        var watch = PlaybackWatchdog()
        watch.rendered()
        XCTAssertNil(watch.check(at: 0, state: .buffering, enabled: true, startupMs: 15000, bufferingMs: 10000))
        XCTAssertNil(watch.check(at: 8, state: .playing, enabled: true, startupMs: 15000, bufferingMs: 10000))
        XCTAssertNil(watch.check(at: 9, state: .buffering, enabled: true, startupMs: 15000, bufferingMs: 10000))
        XCTAssertNil(watch.check(at: 10, state: .buffering, enabled: false, startupMs: 15000, bufferingMs: 10000))
        XCTAssertNil(watch.check(at: 100, state: .buffering, enabled: true, startupMs: 15000, bufferingMs: 10000))
        XCTAssertEqual(watch.check(at: 110, state: .buffering, enabled: true, startupMs: 15000, bufferingMs: 10000), .buffering)
    }
    func testDisableResetCompletionAndReplayProgress() {
        var watch = PlaybackWatchdog()
        XCTAssertNil(watch.check(at: 0, state: .preparing, enabled: true, startupMs: 0, bufferingMs: 0))
        XCTAssertNil(watch.check(at: 1000, state: .buffering, enabled: true, startupMs: 0, bufferingMs: 0))
        watch.begin(position: 100)
        watch.progress(0) // replay seek
        watch.progress(1) // replay may not produce a second first-frame notification
        XCTAssertNil(watch.check(at: 1001, state: .playing, enabled: true, startupMs: 10, bufferingMs: 10))
        watch.progress(2)
        XCTAssertNil(watch.check(at: 2000, state: .playing, enabled: true, startupMs: 10, bufferingMs: 10))
        XCTAssertNil(watch.check(at: 3000, state: .completed, enabled: true, startupMs: 10, bufferingMs: 10))
        watch.begin()
        XCTAssertNil(watch.check(at: 4000, state: .preparing, enabled: true, startupMs: 1000, bufferingMs: 1000))
        XCTAssertEqual(watch.check(at: 4001, state: .preparing, enabled: true, startupMs: 1000, bufferingMs: 1000), .startup)
    }
    func testConfigurationDefaultsAndOverrides() throws {
        let config = try JSONDecoder().decode(VPlayerConfig.self,
            from: Data("{\"startupTimeoutMs\":20000,\"bufferingTimeoutMs\":0}".utf8))
        XCTAssertEqual(config.startupTimeoutMs, 20000)
        XCTAssertEqual(config.bufferingTimeoutMs, 0)
        XCTAssertEqual(VPlayerConfig().startupTimeoutMs, 15000)
        XCTAssertEqual(VPlayerConfig().bufferingTimeoutMs, 15000)
    }
}


extension PlaybackWatchdogTests {
    func testFrozenPlayingDespiteFirstFrameUsesProgressAndRespectsSuspension() {
        var watch = PlaybackWatchdog()
        watch.rendered()
        XCTAssertNil(watch.check(at: 0, state: .playing, enabled: true, startupMs: 1000, bufferingMs: 1000))
        watch.progress(1)
        XCTAssertNil(watch.check(at: 1, state: .playing, enabled: true, startupMs: 1000, bufferingMs: 1000))
        XCTAssertNil(watch.check(at: 2, state: .playing, enabled: true, startupMs: 1000, bufferingMs: 1000))
        watch.suspend()
        XCTAssertNil(watch.check(at: 100, state: .playing, enabled: true, startupMs: 1000, bufferingMs: 1000))
        XCTAssertEqual(watch.check(at: 101, state: .playing, enabled: true, startupMs: 1000, bufferingMs: 1000), .frozen)
    }
}
