import XCTest
@testable import MediaPlayerKit

final class PlayerRequestStatisticsTests: XCTestCase {
    private func collector() -> PlayerRequestStatistics {
        let value = PlayerRequestStatistics()
        value.begin(source: "https://example.com/live.m3u8", type: "hls")
        return value
    }
    func testThresholdHTTPAndUnknownFields() {
        let stats = collector()
        stats.record(PlayerRequestEvent(url: "a", elapsed: 600, status: 206))
        XCTAssertTrue(stats.drain().isEmpty)
        stats.record(PlayerRequestEvent(url: "b", endAt: 2000, elapsed: 600.123, status: 404))
        let logs = stats.drain()
        XCTAssertEqual(logs.map { $0.0 }, ["PlayerSourceRequestStatistics.logSlowRequests",
                                          "PlayerSourceRequestStatistics.logUnexpectedStatusRequests"])
        let slow = logs[0].1["requestInfo"] as? [[String: Any]]
        XCTAssertEqual(slow?.first?["elapsed"] as? Double, 600.123)
        XCTAssertNil(slow?.first?["size"])
        XCTAssertTrue(stats.drain().isEmpty)
    }
    func testRepeatsAcrossWindowsAndSourceIsolation() {
        let stats = collector()
        stats.record(PlayerRequestEvent(url: "a", startAt: 1))
        stats.record(PlayerRequestEvent(url: "a", startAt: 2))
        let first = stats.drain().first?.1["requestInfo"] as? [[Any]]
        XCTAssertEqual((first?.first?[1] as? [String: Any])?["count"] as? Int, 2)
        stats.record(PlayerRequestEvent(url: "a", startAt: 3))
        let next = stats.drain().first?.1["requestInfo"] as? [[Any]]
        XCTAssertEqual((next?.first?[1] as? [String: Any])?["count"] as? Int, 1)
        stats.begin(source: "b", type: "hls")
        stats.record(PlayerRequestEvent(url: "a", startAt: 4))
        XCTAssertTrue(stats.drain().isEmpty)
    }
    func testBoundsCacheAndErrorDomain() {
        let stats = collector()
        stats.record(PlayerRequestEvent(url: "cached", startAt: 1, elapsed: 1000, status: 500, cached: true))
        XCTAssertTrue(stats.drain().isEmpty)
        for n in 0..<50 { stats.record(PlayerRequestEvent(url: "a", startAt: Double(n), elapsed: 700)) }
        let logs = stats.drain()
        XCTAssertEqual((logs[0].1["requestInfo"] as? [[String: Any]])?.count, 5)
        let repeatInfo = (logs[1].1["requestInfo"] as? [[Any]])?.first?[1] as? [String: Any]
        XCTAssertEqual(repeatInfo?["count"] as? Int, 50)
        XCTAssertEqual((repeatInfo?["startAt"] as? [Double])?.count, 30)
        stats.record(PlayerRequestEvent(url: "a", errorCode: 404, errorDomain: "decoder"))
        XCTAssertEqual(stats.drain().first?.0, "PlayerSourceRequestStatistics.logNetworkErrors")
    }
    func testConfigurationDecoding() throws {
        let config = try JSONDecoder().decode(VPlayerConfig.self, from: Data("{\"slowRequestThreshold\":1200}".utf8))
        XCTAssertEqual(config.slowRequestThreshold, 1200)
        XCTAssertEqual(VPlayerConfig().slowRequestThreshold, 600)
    }
}

private final class RequestLogAppender: Appender {
    var messages: [String] = []
    func append(level: LogLevel, tag: String, message: String, messageType: MessageType) {
        messages.append(message)
    }
}

extension PlayerRequestStatisticsTests {
    func testDiagnosticsFlushesRequestsOnSwitchAndDestroyWithoutTimer() {
        let appender = RequestLogAppender()
        Logger.configure { _ in [appender] }
        defer { Logger.destroy() }
        let diagnostics = PlaybackDiagnostics(clock: { 0 })
        diagnostics.configureStatistics(interval: 0)
        diagnostics.begin(source: PlayerSource(url: "https://example.com/a"), engine: .avPlayer)
        diagnostics.request(PlayerRequestEvent(url: "https://example.com/segment", elapsed: 700))
        diagnostics.endAttempt(reason: "switch")
        XCTAssertEqual(appender.messages.filter { $0.contains("logSlowRequests") }.count, 1)
        diagnostics.begin(source: PlayerSource(url: "https://example.com/b"), engine: .avPlayer)
        diagnostics.request(PlayerRequestEvent(url: "https://example.com/b-segment", status: 503))
        diagnostics.finish()
        diagnostics.finish()
        XCTAssertEqual(appender.messages.filter { $0.contains("logUnexpectedStatusRequests") }.count, 1)
        XCTAssertEqual(appender.messages.filter { $0.contains("logSlowRequests") }.count, 1)
    }
}


extension PlayerRequestStatisticsTests {
    func testPlaylistReloadsAreNotAbnormalButKeepSlowAndHTTPFailures() {
        let stats = collector()
        let playlists = [
            ("https://example.com/live.m3u8", "media"),
            ("https://example.com/LIVE.M3U8?token=x#fragment", "media"),
            ("https://example.com/playlist?id=1", "playlist")
        ]
        for (url, kind) in playlists {
            for time in 1...3 {
                stats.record(PlayerRequestEvent(url: url, startAt: Double(time), elapsed: 700,
                                                status: 503, kind: kind))
            }
        }
        let names = stats.drain().map { $0.0 }
        XCTAssertEqual(names, ["PlayerSourceRequestStatistics.logSlowRequests",
                               "PlayerSourceRequestStatistics.logUnexpectedStatusRequests"])
        // Query text mentioning m3u8 must not exempt a media segment.
        let segment = "https://example.com/segment.ts?source=live.m3u8"
        stats.record(PlayerRequestEvent(url: segment, startAt: 4, kind: "segment"))
        stats.record(PlayerRequestEvent(url: segment, startAt: 5, kind: "segment"))
        XCTAssertEqual(stats.drain().map { $0.0 }, ["PlayerSourceRequestStatistics.logAbnormalRequests"])
    }
}
