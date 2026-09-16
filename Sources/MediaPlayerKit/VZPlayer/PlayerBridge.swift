import Foundation
#if canImport(WebKit)
import WebKit
#endif

/// 标准化 WKWebView ➔ IH5Player 跨平台通信桥接协调器 (1:1 对标 Android vzPlayerBridge / PlayerBridge)
@objc(PlayerBridge)
public final class PlayerBridge: NSObject, H5EventListener {
    public weak var player: IH5Player? {
        didSet {
            guard oldValue !== player else { return }
            (oldValue as? H5Player)?.removeH5Listener(self)
            bindingEpoch &+= 1
            commandDestroyed = false
            closed = false
            lastEvent = nil
        }
    }
    /// Explicit event binding. Plain player assignment remains dispatch-only for custom bridges.
    public func bind(player: IH5Player?) {
        self.player = player
        closed = false
        player?.SetOnH5EventListener(self)
    }
    private var bindingEpoch: UInt64 = 0
    private var commandDestroyed = false
    private var closed = false
    private var lastEvent: String?

    /// Disconnects callbacks without destroying the host-owned player or WebView handler.
    public func detach() {
        player = nil
        closed = true
        #if canImport(WebKit)
        webView = nil
        pageGate.invalidate()
        #endif
    }
    #if canImport(WebKit)
    public weak var webView: WKWebView? {
        didSet { if oldValue !== webView { pageGate = BridgePageGate(); pendingHandshakes.removeAll(); webViewEpoch &+= 1 } }
    }
    private var pageGate = BridgePageGate()
    /// When true, rejects legacy messages without pageId once a modern page has handshaken.
    /// Defaults to false (compatible mode) to allow legacy callers to coexist with the modern bridge.
    public var strictPageIsolation: Bool {
        get { pageGate.strict }
        set { pageGate.strict = newValue }
    }
    private var webViewEpoch: UInt64 = 0
    private var pendingHandshakes: [() -> Void] = []
    private var pageID: String? { pageGate.pageID }
    /// Optional host allowlist, applied to the sending main-frame URL.
    public var allowsPage: ((URL) -> Bool)?

    /// Call from didStartProvisionalNavigation; old messages cannot reopen the gate.
    public func invalidatePage() { pageGate.invalidate(); pendingHandshakes.removeAll() }

    /// Call from didCommit, after WebKit replaces the old document (not at navigation start).
    public func commitPage() {
        guard !closed else { return }
        pageGate.commit()
        let pending = pendingHandshakes
        pendingHandshakes.removeAll()
        for resume in pending { resume() }
        webView?.evaluateJavaScript("window.vzPlayerBridge?.ready?.().catch(() => {});", completionHandler: nil)
    }

    private func sendJavaScript(_ script: String) {
        guard !closed, !pageGate.navigating, let target = webView else { return }
        let token = pageID
        let binding = bindingEpoch
        let epoch = pageGate.generation
        let viewEpoch = webViewEpoch
        DispatchQueue.main.async { [weak self, weak target] in
            guard let self = self, let target = target, !self.closed,
                  !self.pageGate.navigating, self.webView === target, self.pageID == token,
                  self.bindingEpoch == binding, self.pageGate.generation == epoch, self.webViewEpoch == viewEpoch else { return }
            let guarded = token.map {
                "if (window.vzPlayerBridge?.pageId === \(Self.jsString($0))) { \(script) }"
            } ?? "if (!window.vzPlayerBridge?.pageId) { \(script) }"
            target.evaluateJavaScript(guarded, completionHandler: nil)
        }
    }

    /// Install before creating/loading WKWebView. Message handler registration remains host-owned.
    public static func installJavaScript(in controller: WKUserContentController) throws {
        #if SWIFT_PACKAGE
        let bundles = [Bundle.module]
        #else
        let bundles = [Bundle(for: PlayerBridge.self), Bundle.main]
        #endif
        guard let url = bundles.compactMap({ $0.url(forResource: "vzplayer-bridge", withExtension: "js") }).first else {
            throw NSError(domain: "MediaPlayerKit.PlayerBridge", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "vzplayer-bridge.js resource is missing"])
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        guard !controller.userScripts.contains(where: { $0.source == source }) else { return }
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    #endif
    
    #if canImport(WebKit)
    public init(player: IH5Player?, webView: WKWebView? = nil) {
        self.player = player
        self.webView = webView
        super.init()
        self.player?.SetOnH5EventListener(self)
    }
    #else
    public init(player: IH5Player?) {
        self.player = player
        super.init()
        self.player?.SetOnH5EventListener(self)
    }
    #endif
    
    // MARK: - H5EventListener 原生向 H5 派发事件回调
    
    public func onStatistics(_ statistics: [String: Any]) {
        #if canImport(WebKit)
        guard let data = try? JSONSerialization.data(withJSONObject: statistics),
              let json = String(data: data, encoding: .utf8) else { return }
        sendJavaScript("window.vzPlayerBridge?.onStatistics?.(\(json));")
        #endif
    }

    public func onEvent(_ eventName: String) {
        lastEvent = eventName
        #if canImport(WebKit)
        sendJavaScript("""
        if (typeof window.vzPlayerBridge?.onEvent === 'function') {
            window.vzPlayerBridge.onEvent(\(Self.jsString(eventName)));
        } else { window.vzPlayerBridge?.triggerEvent?.(\(Self.jsString(eventName))); }
        """)
        #endif
    }

    public func onError(_ code: Int, errMsg: String) {
        #if canImport(WebKit)
        sendJavaScript("""
        if (typeof window.vzPlayerBridge?.onError === 'function') {
            window.vzPlayerBridge.onError(\(code), \(Self.jsString(errMsg)));
        } else { window.vzPlayerBridge?.triggerError?.(\(code), \(Self.jsString(errMsg))); }
        """)
        #endif
    }

    public func onTimeUpdate(_ currentTime: Int64) {
        #if canImport(WebKit)
        sendJavaScript("""
        if (typeof window.vzPlayerBridge?.onTimeUpdate === 'function') {
            window.vzPlayerBridge.onTimeUpdate(\(currentTime));
        } else { window.vzPlayerBridge?.triggerTimeUpdate?.(\(currentTime)); }
        """)
        #endif
    }

    private func readyState(_ player: IH5Player) -> [String: Any] {
        var result: [String: Any] = ["event": lastEvent ?? "", "destroyed": false]
        let h5 = player as? H5Player
        result["state"] = h5?.bridgeState ?? "unknown"
        result["pendingSource"] = h5?.bridgePendingSource ?? false
        result["hasPendingSource"] = result["pendingSource"]
        for json in [player.get_currentTime(), player.get_duration(), player.get_pause(),
                     player.get_volume(), player.get_muted(), player.get_loop(), player.get_speed()] {
            if let fields = parseJSON(json) { result.merge(fields) { _, new in new } }
        }
        result["source"] = parseJSON(player.get_currentsource()) ?? [:]
        result["statistics"] = parseJSON(player.get_statistics?() ?? "{}") ?? [:]
        return result
    }

    // MARK: - 处理来自 JS 的指令分发 (对标 Android @JavascriptInterface)
    
    @discardableResult
    public func handleScriptMessage(method: String, paramsJson: String = "{}") -> String? {
        guard !closed, !commandDestroyed, let player = player,
              (player as? H5Player)?.bridgeIsDestroyed != true else { return nil }
        
        switch method {
        case "play", "Play":
            player.play()
            return nil
        case "pause", "Pause":
            player.pause()
            return nil
        case "resume", "Resume":
            player.resume()
            return nil
        case "destroy", "Destroy":
            commandDestroyed = true
            player.destroy()
            return nil
        case "setCurrentTime", "set_currentTime":
            return player.set_currentTime(paramsJson) ? "true" : "false"
        case "getStatistics", "get_statistics":
            return player.get_statistics?() ?? "{}"
        case "getCurrentTime", "get_currentTime":
            return player.get_currentTime()
        case "getDuration", "get_duration":
            return player.get_duration()
        case "getPause", "get_pause":
            return player.get_pause()
        case "getVolume", "get_volume":
            return player.get_volume()
        case "setVolume", "set_volume":
            return player.set_volume(paramsJson) ? "true" : "false"
        case "getMuted", "get_muted":
            return player.get_muted()
        case "setMuted", "set_muted":
            return player.set_muted(paramsJson) ? "true" : "false"
        case "getVideoWidth", "get_videoWidth":
            return player.get_videoWidth()
        case "getVideoHeight", "get_videoHeight":
            return player.get_videoHeight()
        case "getLoop", "get_loop":
            return player.get_loop()
        case "setLoop", "set_loop":
            return player.set_loop(paramsJson) ? "true" : "false"
        case "getSpeed", "get_speed":
            return player.get_speed()
        case "setSpeed", "set_speed":
            return player.set_speed(paramsJson) ? "true" : "false"
        case "getBuffered", "get_buffered":
            return player.get_buffered()
        case "getCurrentSource", "get_currentsource":
            return player.get_currentsource()
        case "sendEvent", "SendEvent":
            guard let dict = parseJSON(paramsJson), let eventName = dict["eventName"] as? String,
                  eventName == "NEXT_SOURCE" || eventName == "SWITCH_SOURCE",
                  dict["params"] == nil || dict["params"] is [String: Any] else { return "false" }
            let innerParams = dict["params"] as? [String: Any] ?? [:]
            if eventName == "SWITCH_SOURCE" {
                guard let index = innerParams["index"] as? Int ?? innerParams["sourceIndex"] as? Int else { return "false" }
                return player.switchSource(index: index) ? "true" : "false"
            }
            player.SendEvent(eventName, "{}")
            return "true"
        case "switchSource":
            if let dict = parseJSON(paramsJson),
               let idx = dict["index"] as? Int ?? (dict["sourceIndex"] as? Int) {
                return player.switchSource(index: idx) ? "true" : "false"
            }
            return nil
        default:
            return nil
        }
    }
    
    /// Result acknowledgement means the command was handled, not that playback has completed.
    public func handleRequest(method: String, paramsJson: String = "{}", requestId: String) -> [String: Any] {
        let supported: Set<String> = ["bridgeReady", "getStatistics", "get_statistics", "play", "Play", "pause", "Pause", "resume", "Resume", "destroy", "Destroy",
            "setCurrentTime", "set_currentTime", "getCurrentTime", "get_currentTime", "getDuration", "get_duration",
            "getPause", "get_pause", "getVolume", "get_volume", "setVolume", "set_volume", "getMuted", "get_muted",
            "setMuted", "set_muted", "getVideoWidth", "get_videoWidth", "getVideoHeight", "get_videoHeight",
            "getLoop", "get_loop", "setLoop", "set_loop", "getSpeed", "get_speed", "setSpeed", "set_speed",
            "getBuffered", "get_buffered", "getCurrentSource", "get_currentsource", "switchSource", "sendEvent", "SendEvent"]
        guard supported.contains(method) else {
            return ["requestId": requestId, "ok": false, "error": "unsupported_method"]
        }
        guard !closed else { return ["requestId": requestId, "ok": false, "error": "bridge_closed"] }
        guard let player = player else { return ["requestId": requestId, "ok": false, "error": "player_unavailable"] }
        if commandDestroyed || (player as? H5Player)?.bridgeIsDestroyed == true {
            if method == "destroy" || method == "Destroy" {
                return ["requestId": requestId, "ok": true, "result": NSNull()]
            }
            return ["requestId": requestId, "ok": false, "error": "player_destroyed"]
        }
        if method == "bridgeReady" {
            return ["requestId": requestId, "ok": true, "result": readyState(player)]
        }
        let raw = handleScriptMessage(method: method, paramsJson: paramsJson)
        if raw == "false" || (method == "switchSource" && raw == nil) {
            return ["requestId": requestId, "ok": false, "error": "invalid_parameters_or_rejected"]
        }
        let value: Any = raw.flatMap { $0.data(using: .utf8) }.flatMap {
            try? JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed)
        } ?? NSNull()
        return ["requestId": requestId, "ok": true, "result": value]
    }

    /// Shared lifecycle gate for standard and host-defined commands.
    func handleValidatedRequest(method: String, paramsJson: String, requestId: String,
                                customHandler: ((String, String) -> [String: Any]?)?) -> [String: Any] {
        let error: String?
        if closed { error = "bridge_closed" }
        else if player == nil { error = "player_unavailable" }
        else if commandDestroyed || (player as? H5Player)?.bridgeIsDestroyed == true {
            if method == "destroy" || method == "Destroy" {
                return handleRequest(method: method, paramsJson: paramsJson, requestId: requestId)
            }
            error = "player_destroyed"
        } else { error = nil }
        if let error = error { return ["requestId": requestId, "ok": false, "error": error] }
        return customHandler?(method, paramsJson)
            ?? handleRequest(method: method, paramsJson: paramsJson, requestId: requestId)
    }

    #if canImport(WebKit)
    public static func reply(_ response: [String: Any], to webView: WKWebView?) {
        guard let data = try? JSONSerialization.data(withJSONObject: response),
              let json = String(data: data, encoding: .utf8) else { return }
        let script = "window.vzPlayerBridge?.onResponse?.(\(json));"
        let guarded = (response["pageId"] as? String).map {
            "if (window.vzPlayerBridge?.pageId === \(Self.jsString($0))) { \(script) }"
        } ?? script
        webView?.evaluateJavaScript(guarded, completionHandler: nil)
    }
    #endif

    private static func jsString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }
    private func parseJSON(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }
}

#if canImport(WebKit)
extension PlayerBridge: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        handleMessage(message)
    }

    /// Custom commands run only after the same origin, document and lifecycle checks.
    /// Return nil to use the standard SDK dispatcher. Handler executes on the main thread.
    public func handleMessage(_ message: WKScriptMessage,
                              customHandler: ((String, String) -> [String: Any]?)? = nil) {
        guard !closed, message.name == "vzPlayerBridge", message.frameInfo.isMainFrame,
              let target = webView, message.webView === target,
              let dict = message.body as? [String: Any],
              let method = dict["method"] as? String else { return }
        if let allowsPage = allowsPage {
            guard let url = message.frameInfo.request.url, allowsPage(url) else { return }
        }
        if pageGate.navigating {
            // A new document may announce itself before didCommit. Replay only handshakes,
            // then recheck the live document; never queue playback commands from the old page.
            if method == "bridgeReady", dict["pageId"] is String, pendingHandshakes.count < 16 {
                pendingHandshakes.append { [weak self] in self?.handleMessage(message, customHandler: customHandler) }
                return
            }
            if let requestId = dict["requestId"] as? String {
                if let token = dict["pageId"] as? String {
                    target.evaluateJavaScript("window.vzPlayerBridge?.pageId === \(Self.jsString(token))") { [weak self, weak target] value, error in
                        guard error == nil, value as? Bool == true, let target = target, self?.webView === target else { return }
                        var response: [String: Any] = ["requestId": requestId, "ok": false, "error": "page_not_ready", "pageId": token]
                        Self.reply(response, to: target)
                    }
                } else if !self.pageGate.strict {
                    var response: [String: Any] = ["requestId": requestId, "ok": false, "error": "page_not_ready"]
                    Self.reply(response, to: target)
                }
            }
            return
        }
        let paramsJson = dict["paramsJson"] as? String ?? "{}"
        let epoch = pageGate.generation
        let viewEpoch = webViewEpoch
        let binding = bindingEpoch
        let perform: (String?) -> Void = { [weak self, weak target] token in
            guard let self = self, let target = target, !self.closed, self.webView === target, self.pageGate.generation == epoch, self.webViewEpoch == viewEpoch,
                  self.bindingEpoch == binding else { return }
            guard self.pageGate.accept(token, handshake: method == "bridgeReady", generation: epoch) else {
                if let requestId = dict["requestId"] as? String {
                    var response: [String: Any] = ["requestId": requestId, "ok": false, "error": "page_not_ready"]
                    if let token = token { response["pageId"] = token }
                    Self.reply(response, to: target)
                }
                return
            }
            if let requestId = dict["requestId"] as? String {
                var response = self.handleValidatedRequest(method: method, paramsJson: paramsJson,
                    requestId: requestId, customHandler: customHandler)
                response["requestId"] = requestId
                if let token = token { response["pageId"] = token }
                Self.reply(response, to: target)
            } else {
                if !self.commandDestroyed, (self.player as? H5Player)?.bridgeIsDestroyed != true,
                   self.player != nil, customHandler?(method, paramsJson) != nil { return }
                self.handleScriptMessage(method: method, paramsJson: paramsJson)
            }
        }
        if let token = dict["pageId"] as? String {
            // Verify the message still belongs to the currently loaded document.
            target.evaluateJavaScript("window.vzPlayerBridge?.pageId === \(Self.jsString(token))") { value, error in
                guard error == nil, value as? Bool == true else { return }
                perform(token)
            }
        } else {
            // Keep the legacy host bridge contract; it has no document identifier.
            perform(nil)
        }
    }
}
#endif
