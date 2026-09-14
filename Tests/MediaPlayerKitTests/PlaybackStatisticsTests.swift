import XCTest
@testable import MediaPlayerKit

final class PlaybackStatisticsTests: XCTestCase {
    private func number(_ record: [String: Any], _ scope: String, _ field: String) -> Double {
        let fields = record[scope] as? [String: Any] ?? [:]
        return (fields[field] as? NSNumber)?.doubleValue ?? -1
    }
    func testPlayingAndStallingAreDisjointAndSnapshotsDoNotDoubleCount() {
        var time: Double = 0
        let stats = PlaybackStatisticsTracker(clock: { time })
        stats.begin(sourceURL: "https://example.com/a", sourceType: "hls", sourceIndex: 0, engine: "avplayer")
        stats.created()
        time = 1; stats.state(.playing)
        time = 2; stats.state(.playing)
        time = 5; stats.state(.buffering)
        time = 6; stats.state(.buffering); stats.publish()
        XCTAssertEqual(number(stats.latest, "session", "playDurationMs"), 4000)
        XCTAssertEqual(number(stats.latest, "session", "stalledTotalDuration"), 1000)
        XCTAssertEqual(number(stats.latest, "session", "stalledCount"), 1)
        time = 8; stats.state(.paused); stats.publish()
        XCTAssertEqual(number(stats.latest, "session", "stalledTotalDuration"), 3000)
        XCTAssertEqual(number(stats.latest, "window", "stalledTotalDuration"), 2000)
        time = 20; stats.finish(reason: "destroy")
        XCTAssertEqual(number(stats.latest, "session", "playDurationMs"), 4000)
        XCTAssertEqual(number(stats.latest, "session", "stalledTotalDuration"), 3000)
        let sequence = stats.latest["sequence"] as? Int
        time = 30; stats.finish(reason: "destroy"); stats.publish()
        XCTAssertEqual(stats.latest["sequence"] as? Int, sequence)
    }
    func testFallbackPreservesSourceAndSessionAndSettlesRecovery() {
        var time: Double = 0
        let stats = PlaybackStatisticsTracker(clock: { time })
        stats.begin(sourceURL: "https://example.com/a", sourceType: "hls", sourceIndex: 0, engine: "avplayer")
        stats.created(); stats.state(.playing)
        time = 3; stats.failed(error: NSError(domain: "test", code: 1), willRecover: true)
        let oldSource = stats.latest["sourceId"] as? String
        let oldAttempt = stats.latest["attemptId"] as? String
        time = 4
        stats.begin(sourceURL: "https://example.com/a", sourceType: "hls", sourceIndex: 0, engine: "ksmeplayer")
        time = 5; stats.created(); stats.state(.playing); stats.firstFrame()
        XCTAssertEqual(stats.latest["sourceId"] as? String, oldSource)
        XCTAssertNotEqual(stats.latest["attemptId"] as? String, oldAttempt)
        XCTAssertEqual(stats.latest["engineSwitchCount"] as? Int, 1)
        XCTAssertEqual(stats.latest["recoverySuccessCount"] as? Int, 1)
        XCTAssertEqual(stats.latest["recoveryDurationMs"] as? Double, 2000)
        time = 7; stats.publish()
        XCTAssertEqual(number(stats.latest, "session", "playDurationMs"), 5000)
        XCTAssertEqual(number(stats.latest, "attempt", "playDurationMs"), 2000)
        stats.begin(sourceURL: "https://example.com/b", sourceType: "hls", sourceIndex: 1, engine: "avplayer")
        stats.created()
        XCTAssertEqual(number(stats.latest, "source", "playDurationMs"), 0)
        XCTAssertEqual(number(stats.latest, "session", "playDurationMs"), 5000)
        XCTAssertEqual(stats.latest["sourceSwitchCount"] as? Int, 1)
    }
    func testUnknownFieldsAreJSONNullAndRecoveryFailureIsCountedOnce() throws {
        var time: Double = 0
        let stats = PlaybackStatisticsTracker(clock: { time })
        stats.begin(sourceURL: "bad", sourceType: "hls", sourceIndex: 0, engine: "avplayer")
        time = 2; stats.failed(error: NSError(domain: "test", code: 1), willRecover: true)
        stats.begin(sourceURL: "bad", sourceType: "hls", sourceIndex: 0, engine: "ksmeplayer")
        time = 5; stats.failed(error: NSError(domain: "test", code: 2), willRecover: false)
        stats.failed(error: NSError(domain: "test", code: 2), willRecover: false)
        XCTAssertEqual(stats.latest["errorCount"] as? Int, 2)
        XCTAssertEqual(stats.latest["recoveryFailureCount"] as? Int, 1)
        XCTAssertTrue(stats.latest["firstFrameDurationMs"] is NSNull)
        XCTAssertEqual(stats.latest["createOK"] as? Bool, false)
        XCTAssertEqual(stats.latest["requestDetailsAvailable"] as? Bool, false)
        _ = try JSONSerialization.data(withJSONObject: stats.latest)
    }
    func testNewSourcesResetsSessionAndClosesOpenStall() {
        var time: Double = 0
        let stats = PlaybackStatisticsTracker(clock: { time })
        var records: [[String: Any]] = []
        stats.emit = { records.append($0) }
        stats.begin(sourceURL: "a", sourceType: "hls", sourceIndex: 0, engine: "avplayer")
        stats.state(.buffering)
        time = 4; stats.reset()
        XCTAssertEqual(number(records.last ?? [:], "session", "stalledTotalDuration"), 4000)
        let oldID = records.last?["sessionId"] as? String
        stats.begin(sourceURL: "a", sourceType: "hls", sourceIndex: 0, engine: "avplayer")
        stats.created()
        XCTAssertNotEqual(stats.latest["sessionId"] as? String, oldID)
        XCTAssertEqual(number(stats.latest, "session", "stalledCount"), 0)
    }
    func testNativeQoSExcludesPauseAndUnknownNetworkMeasurements() throws {
        var time: Double = 0
        let tracker = QoSAPMTracker(sessionID: "test", mediaURL: URL(string: "https://example.com/a")!,
                                    engineName: "avplayer", clock: { time })
        tracker.markPrepareStart()
        time = 1; tracker.markFirstFrameRendered(); tracker.markPlayStart()
        time = 4; tracker.markBufferingStart(); tracker.markBufferingStart()
        time = 6; tracker.markState(.paused)
        time = 20
        XCTAssertEqual(tracker.snapshot().totalPlayDuration, 3)
        XCTAssertEqual(tracker.snapshot().totalStutterDuration, 2)
        tracker.markPlayStart()
        time = 22
        let report = tracker.finish()
        XCTAssertEqual(report.totalPlayDuration, 5)
        XCTAssertEqual(report.stutterCount, 1)
        time = 30
        XCTAssertEqual(tracker.finish().totalPlayDuration, 5)
        let json = report.toDictionary()
        XCTAssertTrue(json["dns_duration_ms"] is NSNull)
        XCTAssertTrue(json["dropped_frames"] is NSNull)
        _ = try JSONSerialization.data(withJSONObject: json)
        report.dnsDuration = 0
        XCTAssertEqual(report.toDictionary()["dns_duration_ms"] as? Double, 0)
    }
}

extension PlaybackStatisticsTests {
    func testManualCancellationAndCompletedPlaybackCanResumeWithoutInflation() {
        var time: Double = 0
        let stats = PlaybackStatisticsTracker(clock: { time })
        stats.begin(sourceURL: "a", sourceType: "hls", sourceIndex: 0, engine: "avplayer")
        stats.failed(error: NSError(domain: "test", code: 1), willRecover: true)
        stats.cancelRecovery()
        time = 4; stats.begin(sourceURL: "b", sourceType: "hls", sourceIndex: 1, engine: "avplayer")
        stats.state(.playing)
        time = 6; stats.state(.completed)
        time = 10; stats.state(.playing)
        time = 13; stats.finish(reason: "destroy")
        XCTAssertEqual(number(stats.latest, "session", "playDurationMs"), 5000)
        XCTAssertEqual(stats.latest["recoveryCancelledCount"] as? Int, 1)
        XCTAssertEqual(stats.latest["recoverySuccessCount"] as? Int, 0)
    }

    func testDiagnosticsPublishesFinalSnapshotAndStopsAtShutdown() {
        var time: Double = 0
        let diagnostics = PlaybackDiagnostics(clock: { time })
        Logger.configure { _ in [] }
        defer { Logger.destroy() }
        var records: [[String: Any]] = []
        diagnostics.onStatistics = { records.append($0) }
        diagnostics.begin(source: PlayerSource(url: "https://example.com/a"), engine: .avPlayer)
        diagnostics.created()
        diagnostics.state(.playing)
        time = 2; diagnostics.state(.buffering)
        time = 5; diagnostics.finish()
        XCTAssertEqual(records.last?["reason"] as? String, "sessionEnded:destroy")
        XCTAssertEqual(number(records.last ?? [:], "session", "playDurationMs"), 2000)
        XCTAssertEqual(number(records.last ?? [:], "session", "stalledTotalDuration"), 3000)
        let count = records.count
        time = 10; diagnostics.finish()
        XCTAssertEqual(records.count, count)
    }

    func testPeriodicStatisticsIsQuietUnlessStallsOccur() {
        var time: Double = 0
        let stats = PlaybackStatisticsTracker(clock: { time })
        var publishedRecords: [[String: Any]] = []
        stats.emit = { publishedRecords.append($0) }

        stats.begin(sourceURL: "https://example.com/live.m3u8", sourceType: "hls", sourceIndex: 0, engine: "avplayer")
        stats.created()
        XCTAssertEqual(publishedRecords.last?["reason"] as? String, "created")
        XCTAssertEqual(publishedRecords.last?["reportable"] as? Bool, true)
        XCTAssertTrue(PlaybackStatisticsTracker.isReportable(publishedRecords.last ?? [:]))

        time = 1
        stats.firstFrame()
        XCTAssertEqual(publishedRecords.last?["reason"] as? String, "firstFrame")
        XCTAssertEqual(publishedRecords.last?["reportable"] as? Bool, true)

        stats.state(.playing)

        // 10s passes: healthy steady playback, no stall in window
        time = 11
        stats.publish()
        XCTAssertEqual(publishedRecords.last?["reason"] as? String, "periodic")
        XCTAssertEqual(publishedRecords.last?["reportable"] as? Bool, false)
        XCTAssertFalse(PlaybackStatisticsTracker.isReportable(publishedRecords.last ?? [:]))

        // 20s passes: still smooth, no stall
        time = 21
        stats.publish()
        XCTAssertEqual(publishedRecords.last?["reportable"] as? Bool, false)
        XCTAssertFalse(PlaybackStatisticsTracker.isReportable(publishedRecords.last ?? [:]))

        // Stall occurs in window
        time = 25
        stats.state(.buffering)
        time = 27
        stats.state(.playing)
        time = 31
        stats.publish()
        XCTAssertEqual(publishedRecords.last?["reason"] as? String, "periodic")
        XCTAssertEqual(publishedRecords.last?["reportable"] as? Bool, true)
        XCTAssertTrue(PlaybackStatisticsTracker.isReportable(publishedRecords.last ?? [:]))
    }
}
