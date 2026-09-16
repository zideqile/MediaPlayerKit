import XCTest
@testable import MediaPlayerKit

private final class H5LogRecorder: Appender {
    var entries: [(String, String)] = []
    func append(level: LogLevel, tag: String, message: String, messageType: MessageType) { entries.append((tag, message)) }
}
final class H5BridgeTests: XCTestCase {
    override func tearDown() { Logger.destroy(); super.tearDown() }
    func testBridgeRejectsCommandsAfterDestroyAndCanRebind() {
        let first = H5Player(playerView: MediaPlayerView())
        let bridge = PlayerBridge(player: first)
        XCTAssertEqual(bridge.handleRequest(method: "destroy", requestId: "1")["ok"] as? Bool, true)
        XCTAssertEqual(bridge.handleRequest(method: "play", requestId: "2")["error"] as? String, "player_destroyed")
        XCTAssertEqual(bridge.handleRequest(method: "destroy", requestId: "3")["ok"] as? Bool, true)
        let next = H5Player(playerView: MediaPlayerView())
        defer { next.destroy() }
        bridge.bind(player: next)
        XCTAssertEqual(bridge.handleRequest(method: "getVolume", requestId: "4")["ok"] as? Bool, true)
        bridge.detach()
        XCTAssertEqual(bridge.handleRequest(method: "getVolume", requestId: "5")["error"] as? String, "bridge_closed")
    }

    func testBridgeDetectsNativeDestructionAndReadySnapshot() {
        let player = H5Player(playerView: MediaPlayerView())
        let bridge = PlayerBridge(player: player)
        _ = player.set_muted("{\"muted\":true}")
        bridge.onEvent("pause")
        let response = bridge.handleRequest(method: "bridgeReady", requestId: "ready")
        let snapshot = response["result"] as? [String: Any]
        XCTAssertEqual(snapshot?["muted"] as? Bool, true)
        XCTAssertEqual(snapshot?["event"] as? String, "pause")
        player.destroy()
        XCTAssertEqual(bridge.handleRequest(method: "play", requestId: "play")["error"] as? String, "player_destroyed")
    }

    func testDispatchOnlyAssignmentDoesNotStealCustomListener() {
        let player = H5Player(playerView: MediaPlayerView())
        defer { player.destroy() }
        let listener = BridgeEventRecorder()
        player.SetOnH5EventListener(listener)
        let bridge = PlayerBridge(player: nil)
        bridge.player = player
        _ = bridge.handleRequest(method: "getVolume", requestId: "query")
        player.onStateChanged(state: .paused)
        bridge.detach()
        player.onStateChanged(state: .playing)
        XCTAssertEqual(listener.events, ["pause", "playing"])
    }

    func testDetachDoesNotClearAnotherListener() {
        let player = H5Player(playerView: MediaPlayerView())
        defer { player.destroy() }
        let bridge = PlayerBridge(player: player)
        let replacement = BridgeEventRecorder()
        player.SetOnH5EventListener(replacement)
        bridge.detach()
        player.onStateChanged(state: .paused)
        XCTAssertEqual(replacement.events, ["pause"])
    }

    func testH5FailuresSharePlayerLogGroupAndPreserveCaller() {
        let recorder = H5LogRecorder()
        Logger.configure { _ in [recorder] }
        let player = H5Player(playerView: MediaPlayerView())
        defer { player.destroy() }
        XCTAssertTrue(player.set_volume("{\"volume\":0.5}"))
        XCTAssertFalse(player.set_volume("{}"))
        XCTAssertEqual(Set(recorder.entries.map { $0.0 }).count, 1)
        XCTAssertTrue(recorder.entries.contains { $0.1.contains("H5Player.set_volume:") && $0.1.contains("invalid parameters") })
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

private final class BridgeEventRecorder: NSObject, H5EventListener {
    var events: [String] = []
    func onEvent(_ name: String) { events.append(name) }
    func onError(_ code: Int, errMsg: String) {}
    func onTimeUpdate(_ currentTime: Int64) {}
}
