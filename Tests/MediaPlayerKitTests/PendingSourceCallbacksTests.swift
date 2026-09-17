import XCTest
@testable import MediaPlayerKit

final class PendingSourceCallbacksTests: XCTestCase {
    func testDisplayedControllerForwardsStateWithoutNewSessionStatisticsOrRecovery() throws {
        let output = PendingOutputRecorder()
        Logger.configure { _ in [output] }
        defer { Logger.destroy() }
        let player = MultiSourcePlayer(playerView: MediaPlayerView())
        defer { player.Destroy() }
        let events = PendingEventRecorder()
        player.AddEventListener(events)
        var constructed: MediaPlayerController?
        player.makeController = { config in
            let controller = MediaPlayerController(config: config)
            constructed = controller
            return controller
        }
        // Local nonexistent media avoids dependence on a remote streaming server.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4").absoluteString
        player.setSources([PlayerSource(url: url, type: "mp4")])
        player.Play()
        let old = try XCTUnwrap(constructed)
        player.setSources([PlayerSource(url: url + "-next", type: "mp4")])
        events.states.removeAll(); events.reports = 0; output.samples = 0
        for state: PlayerState in [.paused, .playing, .buffering, .completed] {
            player.player(old, stateDidChange: state)
        }
        player.player(old, currentTime: 12, totalDuration: 20)
        player.playerDidPlayToEndTime(old)
        player.player(old, didOccurError: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
        old.requestEventHandler?(PlayerRequestEvent(url: url, elapsed: 100, size: 1024, status: 200, kind: "segment"))
        XCTAssertEqual(events.states, [.paused, .playing, .buffering, .completed, .error])
        XCTAssertEqual(events.time, 12)
        XCTAssertEqual(events.ends, 1)
        XCTAssertEqual(events.reports, 0)
        XCTAssertEqual(output.samples, 0)
        XCTAssertEqual(events.recoveries, 0)
        XCTAssertTrue(player.failureHistory.isEmpty)
        XCTAssertTrue(player.hasPendingSource)

        player.Play()
        let stateCount = events.states.count
        player.player(old, stateDidChange: .paused)
        XCTAssertEqual(events.states.count, stateCount) // Replaced controllers stay ignored.
        XCTAssertFalse(player.hasPendingSource)
    }
}
private final class PendingOutputRecorder: Appender {
    var samples = 0
    func append(level: LogLevel, tag: String, message: String, messageType: MessageType) {}
    func appendStatLog(level: LogLevel, tag: String, name: String, data: Double) { samples += 1 }
}
private final class PendingEventRecorder: NSObject, PlayerEventListener {
    var states: [PlayerState] = []
    var time: Int64 = 0
    var ends = 0
    var reports = 0
    var recoveries = 0
    func onStateChanged(state: PlayerState) { states.append(state) }
    func onFirstFrameRendered() {}
    func onTimeUpdate(currentTime: Int64, totalDuration: Int64) { time = currentTime }
    func onError(code: Int, errMsg: String) {}
    func onPlayToEnd() { ends += 1 }
    func onSourceSwitched(source: PlayerSource) {}
    func onWarnMessage(msg: String) {}
    func onStatistics(_ statistics: [String: Any]) { reports += 1 }
    func onRecoveryStarted(_ failure: PlaybackAttemptFailure) { recoveries += 1 }
}
