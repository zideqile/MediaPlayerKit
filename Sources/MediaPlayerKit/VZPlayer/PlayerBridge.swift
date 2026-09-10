import Foundation
#if canImport(WebKit)
import WebKit
#endif

/// 标准化 WKWebView ➔ IH5Player 跨平台通信桥接协调器 (1:1 对标 Android vzPlayerBridge / PlayerBridge)
@objc(PlayerBridge)
public final class PlayerBridge: NSObject, H5EventListener {
    public weak var player: IH5Player?
    #if canImport(WebKit)
    public weak var webView: WKWebView?
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
    
    public func onEvent(_ eventName: String) {
        #if canImport(WebKit)
        DispatchQueue.main.async { [weak self] in
            guard let webView = self?.webView else { return }
            let js = """
            if (window.vzPlayerBridge && typeof window.vzPlayerBridge.onEvent === 'function') {
                window.vzPlayerBridge.onEvent(\(Self.jsString(eventName)));
            } else if (window.vzPlayerBridge && typeof window.vzPlayerBridge.triggerEvent === 'function') {
                window.vzPlayerBridge.triggerEvent(\(Self.jsString(eventName)));
            }
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
        #endif
    }
    
    public func onError(_ code: Int, errMsg: String) {
        #if canImport(WebKit)
        DispatchQueue.main.async { [weak self] in
            guard let webView = self?.webView else { return }
            let js = """
            if (window.vzPlayerBridge && typeof window.vzPlayerBridge.onError === 'function') {
                window.vzPlayerBridge.onError(\(code), \(Self.jsString(errMsg)));
            } else if (window.vzPlayerBridge && typeof window.vzPlayerBridge.triggerError === 'function') {
                window.vzPlayerBridge.triggerError(\(code), \(Self.jsString(errMsg)));
            }
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
        #endif
    }
    
    public func onTimeUpdate(_ currentTime: Int64) {
        #if canImport(WebKit)
        DispatchQueue.main.async { [weak self] in
            guard let webView = self?.webView else { return }
            let js = """
            if (window.vzPlayerBridge && typeof window.vzPlayerBridge.onTimeUpdate === 'function') {
                window.vzPlayerBridge.onTimeUpdate(\(currentTime));
            } else if (window.vzPlayerBridge && typeof window.vzPlayerBridge.triggerTimeUpdate === 'function') {
                window.vzPlayerBridge.triggerTimeUpdate(\(currentTime));
            }
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
        #endif
    }
    
    // MARK: - 处理来自 JS 的指令分发 (对标 Android @JavascriptInterface)
    
    @discardableResult
    public func handleScriptMessage(method: String, paramsJson: String = "{}") -> String? {
        guard let player = player else { return nil }
        
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
            player.destroy()
            return nil
        case "setCurrentTime", "set_currentTime":
            return player.set_currentTime(paramsJson) ? "true" : "false"
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
        let supported: Set<String> = ["play", "Play", "pause", "Pause", "resume", "Resume", "destroy", "Destroy",
            "setCurrentTime", "set_currentTime", "getCurrentTime", "get_currentTime", "getDuration", "get_duration",
            "getPause", "get_pause", "getVolume", "get_volume", "setVolume", "set_volume", "getMuted", "get_muted",
            "setMuted", "set_muted", "getVideoWidth", "get_videoWidth", "getVideoHeight", "get_videoHeight",
            "getLoop", "get_loop", "setLoop", "set_loop", "getSpeed", "get_speed", "setSpeed", "set_speed",
            "getBuffered", "get_buffered", "getCurrentSource", "get_currentsource", "switchSource", "sendEvent", "SendEvent"]
        guard supported.contains(method) else {
            return ["requestId": requestId, "ok": false, "error": "unsupported_method"]
        }
        guard player != nil else { return ["requestId": requestId, "ok": false, "error": "player_unavailable"] }
        let raw = handleScriptMessage(method: method, paramsJson: paramsJson)
        if raw == "false" || (method == "switchSource" && raw == nil) {
            return ["requestId": requestId, "ok": false, "error": "invalid_parameters_or_rejected"]
        }
        let value: Any = raw.flatMap { $0.data(using: .utf8) }.flatMap {
            try? JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed)
        } ?? NSNull()
        return ["requestId": requestId, "ok": true, "result": value]
    }

    #if canImport(WebKit)
    public static func reply(_ response: [String: Any], to webView: WKWebView?) {
        guard let data = try? JSONSerialization.data(withJSONObject: response),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.vzPlayerBridge?.onResponse?.(\(json));", completionHandler: nil)
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
        guard message.name == "vzPlayerBridge",
              let dict = message.body as? [String: Any],
              let method = dict["method"] as? String else {
            return
        }
        let paramsJson = dict["paramsJson"] as? String ?? "{}"
        if let requestId = dict["requestId"] as? String {
            Self.reply(handleRequest(method: method, paramsJson: paramsJson, requestId: requestId), to: webView)
        } else {
            handleScriptMessage(method: method, paramsJson: paramsJson)
        }
    }
}
#endif
