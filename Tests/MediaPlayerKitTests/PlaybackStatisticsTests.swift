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
        XCTAssertEqual(number(stats.latest, "session", "play_ms"), 4000)
        XCTAssertEqual(number(stats.latest, "session", "stalledTotalDuration"), 1000)
        XCTAssertEqual(number(stats.latest, "session", "stalledCount"), 1)
        time = 8; stats.state(.paused); stats.publish()
        XCTAssertEqual(number(stats.latest, "session", "stalledTotalDuration"), 3000)
        XCTAssertEqual(number(stats.latest, "window", "stalledTotalDuration"), 2000)
        time = 20; stats.finish(reason: "destroy")
        XCTAssertEqual(number(stats.latest, "session", "play_ms"), 4000)
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
        XCTAssertEqual(stats.latest["engine_switches"] as? Int, 1)
        XCTAssertEqual(stats.latest["recover_ok"] as? Int, 1)
        XCTAssertEqual(stats.latest["recover_ms"] as? Double, 2000)
        time = 7; stats.publish()
        XCTAssertEqual(number(stats.latest, "session", "play_ms"), 5000)
        XCTAssertEqual(number(stats.latest, "attempt", "play_ms"), 2000)
        stats.begin(sourceURL: "https://example.com/b", sourceType: "hls", sourceIndex: 1, engine: "avplayer")
        stats.created()
        XCTAssertEqual(number(stats.latest, "source", "play_ms"), 0)
        XCTAssertEqual(number(stats.latest, "session", "play_ms"), 5000)
        XCTAssertEqual(stats.latest["source_switches"] as? Int, 1)
    }
    func testUnknownFieldsAreJSONNullAndRecoveryFailureIsCountedOnce() throws {
        var time: Double = 0
        let stats = PlaybackStatisticsTracker(clock: { time })
        stats.begin(sourceURL: "bad", sourceType: "hls", sourceIndex: 0, engine: "avplayer")
        time = 2; stats.failed(error: NSError(domain: "test", code: 1), willRecover: true)
        stats.begin(sourceURL: "bad", sourceType: "hls", sourceIndex: 0, engine: "ksmeplayer")
        time = 5; stats.failed(error: NSError(domain: "test", code: 2), willRecover: false)
        stats.failed(error: NSError(domain: "test", code: 2), willRecover: false)
        XCTAssertEqual(stats.latest["errors"] as? Int, 2)
        XCTAssertEqual(stats.latest["recover_fail"] as? Int, 1)
        XCTAssertTrue(stats.latest["first_frame_time"] is NSNull)
        XCTAssertEqual(stats.latest["createOK"] as? Bool, false)
        XCTAssertEqual(stats.latest["request_details"] as? Bool, false)
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
        XCTAssertTrue(json["dns_ms"] is NSNull)
        XCTAssertTrue(json["dropped_frames"] is NSNull)
        _ = try JSONSerialization.data(withJSONObject: json)
        report.dnsDuration = 0
        XCTAssertEqual(report.toDictionary()["dns_ms"] as? Double, 0)
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
        XCTAssertEqual(number(stats.latest, "session", "play_ms"), 5000)
        XCTAssertEqual(stats.latest["recover_cancel"] as? Int, 1)
        XCTAssertEqual(stats.latest["recover_ok"] as? Int, 0)
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
        XCTAssertTrue(records.contains { $0["reason"] as? String == "sessionEnded:destroy" })
        XCTAssertEqual(records.last?["reason"] as? String, "lifetimeEnded")
        XCTAssertEqual(number(records.last ?? [:], "session", "play_ms"), 2000)
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


extension PlaybackStatisticsTests {
    func testVersionTwoKeepsReferenceFieldsAndRemovesOldCustomKeys() {
        let tracker = PlaybackStatisticsTracker(clock: { 0 })
        tracker.begin(sourceURL: "a", sourceType: "hls", sourceIndex: 0, engine: "avplayer")
        tracker.created(); tracker.firstFrame()
        let record = tracker.latest
        XCTAssertEqual(record["schemaVersion"] as? Int, 2)
        XCTAssertEqual(record["first_frame_time"] as? Double, 0)
        XCTAssertEqual(record["recover_ok"] as? Int, 0)
        XCTAssertNil(record["firstFrameDurationMs"])
        XCTAssertNil(record["recoverySuccessCount"])
        let session = record["session"] as? [String: Any]
        XCTAssertNotNil(session?["stalledTotalDuration"])
        XCTAssertNotNil(session?["stalledCount"])
        XCTAssertNotNil(session?["play_ms"])
    }
}

extension PlaybackStatisticsTests {
    func testWebStyleLogsSeparateSummariesAndKeepQuietDuringSmoothPlayback() {
        let record: [String: Any] = ["reason": "switch", "attemptEnded": true, "sourceIndex": 0, "engine": "ksmeplayer",
            "attempt": ["play_ms": 1043266.6, "stall_ratio": 0.000632],
            "window": ["stalledCount": 0, "stalledTotalDuration": 0.0]]
        let logs = PlaybackStatisticsLog.records(from: record)
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.name, "playtime")
        XCTAssertEqual(logs.first?.fields["totalPlayTime"] as? String, "1043.27s")
        XCTAssertEqual(LogFormatter.formatValue(logs.first?.fields["stall_pct"] ?? NSNull()), "0.06%")
        XCTAssertNil(logs.first?.fields["session"])
        XCTAssertNil(logs.first?.fields["metrics"])
        var periodic = record; periodic["reason"] = "periodic"; periodic["attemptEnded"] = false
        XCTAssertTrue(PlaybackStatisticsLog.records(from: periodic).isEmpty)
        periodic["window"] = ["stalledCount": 1, "stalledTotalDuration": 100.25]
        let stall = PlaybackStatisticsLog.records(from: periodic)
        XCTAssertEqual(stall.count, 1)
        XCTAssertEqual(stall.first?.name, "StalledSummaryInfoStatistics.summarize")
        XCTAssertEqual(stall.first?.fields["stalledTotalDuration"] as? String, "100.25ms")
    }
}


extension PlaybackStatisticsTests {
    func testLifetimeAcrossSessionsAndExactlyOnceAttemptSettlement() {
        var now: Double = 0
        let tracker = PlaybackStatisticsTracker(clock: { now })
        var logs: [PlaybackStatisticsLog] = []
        tracker.emit = { logs += PlaybackStatisticsLog.records(from: $0) }
        tracker.begin(sourceURL: "a", sourceType: "hls", sourceIndex: 0, engine: "avplayer")
        tracker.state(.playing)
        now = 2; tracker.state(.completed)
        tracker.state(.playing)
        now = 3; tracker.reset()
        tracker.begin(sourceURL: "b", sourceType: "hls", sourceIndex: 0, engine: "ksmeplayer")
        tracker.state(.playing)
        now = 7; tracker.state(.paused)
        now = 10; tracker.finish(reason: "destroy")
        tracker.finish(reason: "destroy")
        let attempts = logs.filter { $0.fields["scope"] as? String == "attempt" }
        XCTAssertEqual(attempts.count, 3)
        let finalAttempts = attempts.filter { ["newSources", "destroy"].contains($0.fields["reason"] as? String) }
        XCTAssertEqual(finalAttempts.count, 2)
        XCTAssertEqual(finalAttempts.map { $0.fields["totalPlayTime"] as? String }, ["3s", "4s"])
        let totals = logs.filter { $0.fields["scope"] as? String == "lifetime" }
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals.first?.fields["totalPlayTime"] as? String, "7s")
        XCTAssertEqual(totals.first?.fields["attempts"] as? Int, 2)
    }

    func testDestroyAfterResetWithoutNewPlayerKeepsLifetime() {
        var now: Double = 0
        let tracker = PlaybackStatisticsTracker(clock: { now })
        tracker.begin(sourceURL: "a", sourceType: "hls", sourceIndex: 0, engine: "avplayer")
        tracker.state(.playing)
        now = 2; tracker.reset()
        now = 10; tracker.finish(reason: "destroy")
        let lifetime = tracker.latest["lifetime"] as? [String: Any]
        XCTAssertEqual(lifetime?["play_ms"] as? Double, 2000)
        XCTAssertEqual(tracker.latest["reason"] as? String, "lifetimeEnded")
    }
}


extension PlaybackStatisticsTests {
    func testTerminalAttemptLogsOnceBeforeDestroy() {
        var now: Double = 0
        let tracker = PlaybackStatisticsTracker(clock: { now })
        var logs: [PlaybackStatisticsLog] = []
        tracker.emit = { logs += PlaybackStatisticsLog.records(from: $0) }
        tracker.begin(sourceURL: "a", sourceType: "hls", sourceIndex: 0, engine: "avplayer")
        tracker.state(.playing)
        now = 1; tracker.endAttempt(reason: "terminalError")
        now = 4; tracker.finish(reason: "destroy")
        let attempts = logs.filter { $0.fields["scope"] as? String == "attempt" }
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(attempts.first?.fields["reason"] as? String, "terminalError")
        XCTAssertEqual(attempts.first?.fields["totalPlayTime"] as? String, "1s")
    }

    func testPlaybackDurationSettlementAtKeyEventsAcrossDimensions() {
        var now: Double = 0
        let tracker = PlaybackStatisticsTracker(clock: { now })
        var logs: [PlaybackStatisticsLog] = []
        tracker.emit = { logs += PlaybackStatisticsLog.records(from: $0) }

        tracker.begin(sourceURL: "https://example.com/1.m3u8", sourceType: "hls", sourceIndex: 0, engine: "avplayer")
        tracker.state(.playing)

        now = 5; tracker.state(.paused); tracker.pause()
        let pauseLogs = logs.filter { $0.fields["reason"] as? String == "paused" }
        XCTAssertEqual(pauseLogs.count, 3)
        XCTAssertEqual(pauseLogs.first { $0.fields["scope"] as? String == "attempt" }?.fields["totalPlayTime"] as? String, "5s")
        XCTAssertEqual(pauseLogs.first { $0.fields["scope"] as? String == "source" }?.fields["totalPlayTime"] as? String, "5s")
        XCTAssertEqual(pauseLogs.first { $0.fields["scope"] as? String == "session" }?.fields["totalPlayTime"] as? String, "5s")

        now = 8; tracker.state(.playing)
        now = 11; tracker.seek()
        let seekLogs = logs.filter { $0.fields["reason"] as? String == "seek" }
        XCTAssertEqual(seekLogs.count, 3)
        XCTAssertEqual(seekLogs.first { $0.fields["scope"] as? String == "attempt" }?.fields["totalPlayTime"] as? String, "8s")

        now = 12; tracker.failed(error: NSError(domain: "test", code: -1), willRecover: true)
        let errorLogs = logs.filter { $0.fields["reason"] as? String == "error" }
        XCTAssertEqual(errorLogs.count, 3)
        XCTAssertEqual(errorLogs.first { $0.fields["scope"] as? String == "attempt" }?.fields["totalPlayTime"] as? String, "9s")
    }
}


extension PlaybackStatisticsTests {
    func testReadablePlaybackScopesAndSourceEngineHistory() throws {
        var now: Double = 0
        let tracker = PlaybackStatisticsTracker(clock: { now })
        let url = "https://example.com/live.m3u8"
        tracker.begin(sourceURL: url, sourceType: "hls", sourceIndex: 0, engine: "avplayer")
        tracker.state(.playing)
        now = 1
        tracker.begin(sourceURL: url, sourceType: "hls", sourceIndex: 0, engine: "ksmeplayer")
        tracker.state(.playing)
        now = 2; tracker.endAttempt(reason: "switch")
        let snapshot = tracker.latest
        XCTAssertEqual(snapshot["sourceEngines"] as? [String], ["avplayer", "ksmeplayer"])
        let logs = PlaybackStatisticsLog.records(from: snapshot)
        for scope in ["attempt", "source", "session"] {
            let entry = try XCTUnwrap(logs.first { $0.fields["scope"] as? String == scope })
            let id = try XCTUnwrap(snapshot[scope + "Id"] as? String)
            XCTAssertEqual(entry.fields[scope + "Id"] as? String, String(id.prefix { $0 != "-" }))
            XCTAssertTrue(id.contains("-"))
            XCTAssertEqual(entry.fields["stall_pct"] as? String, "0%")
            if scope != "session" { XCTAssertEqual(entry.fields["sourceUrl"] as? String, url) }
        }
        XCTAssertEqual(logs.first { $0.fields["scope"] as? String == "attempt" }?.fields["engine"] as? String, "ksmeplayer")
        XCTAssertEqual(logs.first { $0.fields["scope"] as? String == "source" }?.fields["engines"] as? [String], ["avplayer", "ksmeplayer"])
        tracker.begin(sourceURL: "https://example.com/other", sourceType: "hls", sourceIndex: 1, engine: "avplayer")
        tracker.publish()
        XCTAssertEqual(tracker.latest["sourceEngines"] as? [String], ["avplayer"])
        let example: [String: Any] = ["reason": "switch", "attemptEnded": true,
            "attempt": ["play_ms": 112501.98, "stall_ratio": 0.001]]
        let log = try XCTUnwrap(PlaybackStatisticsLog.records(from: example).first)
        XCTAssertEqual(log.fields["totalPlayTime"] as? String, "112.50s")
        XCTAssertEqual(log.fields["stall_pct"] as? String, "0.10%")
    }
}


extension PlaybackStatisticsTests {
    func testSourceSwitchDoesNotRepeatPlaytimeAtSourceEndedAndUsesStableOrder() throws {
        var now: Double = 0
        let tracker = PlaybackStatisticsTracker(clock: { now })
        var snapshots: [[String: Any]] = []
        tracker.emit = { snapshots.append($0) }
        tracker.begin(sourceURL: "https://example.com/a", sourceType: "hls", sourceIndex: 0, engine: "avplayer")
        tracker.state(.playing)
        snapshots.removeAll()
        now = 1; tracker.endAttempt(reason: "switch")
        tracker.begin(sourceURL: "https://example.com/b", sourceType: "hls", sourceIndex: 1, engine: "ksmeplayer")
        XCTAssertTrue(snapshots.contains { $0["reason"] as? String == "sourceEnded" })
        let logs = snapshots.flatMap { PlaybackStatisticsLog.records(from: $0) }.filter { $0.name == "playtime" }
        XCTAssertEqual(logs.count, 3)
        XCTAssertEqual(logs.compactMap { $0.fields["scope"] as? String }, ["attempt", "source", "session"])
        for log in logs {
            let scope = try XCTUnwrap(log.fields["scope"] as? String)
            XCTAssertTrue(log.formattedFields.hasPrefix("scope: \(scope), reason: switch, totalPlayTime: 1s, stall_pct: 0%, \(scope)Id:"))
        }
        XCTAssertTrue(logs[0].formattedFields.contains("sourceIndex: 0, engine: avplayer, sourceUrl: https://example.com/a"))
        XCTAssertTrue(logs[1].formattedFields.contains("sourceIndex: 0, engines: [avplayer], sourceUrl: https://example.com/a"))
    }
}
