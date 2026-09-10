import XCTest
@testable import MediaPlayerKit

private final class H5LogRecorder: Appender {
    var entries: [(String, String)] = []
    func append(level: LogLevel, tag: String, message: String, messageType: MessageType) { entries.append((tag, message)) }
}
final class H5BridgeTests: XCTestCase {
    override func tearDown() { Logger.destroy(); super.tearDown() }
    func testH5FailuresSharePlayerLogGroupAndPreserveCaller() {
        let recorder = H5LogRecorder()
        Logger.configure { _ in [recorder] }
        let player = H5Player(playerView: MediaPlayerView())
        defer { player.destroy() }
        XCTAssertTrue(player.set_volume("{\"volume\":0.5}"))
        XCTAssertFalse(player.set_volume("{}"))
        XCTAssertEqual(Set(recorder.entries.map { $0.0 }).count, 1)
        XCTAssertTrue(recorder.entries.contains { $0.1.contains("H5Player.set_volume(_:):") && $0.1.contains("invalid parameters") })
        XCTAssertTrue(recorder.entries.contains { $0.1.contains("set_volume: 0.5") })
    }

    func testSettersRejectInvalidValuesWithoutChangingState() {
        let player = H5Player(playerView: MediaPlayerView())
        defer { player.destroy() }
        XCTAssertTrue(player.set_volume("{\"volume\":0.5}"))
        for json in ["broken", "[]", "{}", "{\"volume\":true}", "{\"volume\":2}"] {
            XCTAssertFalse(player.set_volume(json))
        }
        XCTAssertEqual(player.GetVolume(), 0.5)
        XCTAssertFalse(player.set_currentTime("{\"currentTime\":1e30}"))
        XCTAssertFalse(player.set_currentTime("{\"currentTime\":-1}"))
        XCTAssertFalse(player.set_speed("{\"speed\":0}"))
        XCTAssertFalse(player.set_muted("{\"muted\":1}"))
        XCTAssertTrue(player.set_muted("{\"muted\":true}"))
        XCTAssertTrue(player.IsMuted())
    }
    func testBridgeReturnsStructuredGetterSetterAndFailureResults() {
        let player = H5Player(playerView: MediaPlayerView())
        defer { player.destroy() }
        let bridge = PlayerBridge(player: player)
        XCTAssertEqual(bridge.handleScriptMessage(method: "setVolume", paramsJson: "{\"volume\":0.5}"), "true")
        let result = bridge.handleRequest(method: "getVolume", requestId: "query-1")
        XCTAssertEqual(result["requestId"] as? String, "query-1")
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertEqual((result["result"] as? [String: Any])?["volume"] as? Double, 0.5)
        XCTAssertEqual(bridge.handleRequest(method: "setVolume", paramsJson: "{}", requestId: "2")["ok"] as? Bool, false)
        XCTAssertEqual(bridge.handleRequest(method: "switchSource", paramsJson: "{}", requestId: "3")["ok"] as? Bool, false)
        XCTAssertEqual(bridge.handleRequest(method: "missing", requestId: "4")["error"] as? String, "unsupported_method")
        bridge.player = nil
        XCTAssertEqual(bridge.handleRequest(method: "getVolume", requestId: "5")["error"] as? String, "player_unavailable")
    }
}
