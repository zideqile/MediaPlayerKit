import Foundation
#if canImport(WebKit)
import WebKit
#endif

/// 标准化 WKWebView ➔ IPlayer 跨平台通信桥接协调器 (1:1 对标 Android vzPlayerBridge)
public final class VZPlayerBridge: NSObject, VZH5EventListener {
    public weak var player: IPlayer?
    #if canImport(WebKit)
    public weak var webView: WKWebView?
    #endif
    
    #if canImport(WebKit)
    public init(player: IPlayer?, webView: WKWebView? = nil) {
        self.player = player
        self.webView = webView
        super.init()
        self.player?.SetOnH5EventListener(self)
    }
    #else
    public init(player: IPlayer?) {
        self.player = player
        super.init()
        self.player?.SetOnH5EventListener(self)
    }
    #endif
    
    // MARK: - VZH5EventListener 原生向 H5 派发事件回调
    
    public func onEvent(_ eventName: String) {
        #if canImport(WebKit)
        DispatchQueue.main.async { [weak self] in
            guard let webView = self?.webView else { return }
            let js = """
            if (window.vzPlayerBridge && typeof window.vzPlayerBridge.onEvent === 'function') {
                window.vzPlayerBridge.onEvent('\(eventName)');
            } else if (window.vzPlayerBridge && typeof window.vzPlayerBridge.triggerEvent === 'function') {
                window.vzPlayerBridge.triggerEvent('\(eventName)');
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
            let escapedMsg = errMsg.replacingOccurrences(of: "'", with: "\\'")
            let js = """
            if (window.vzPlayerBridge && typeof window.vzPlayerBridge.onError === 'function') {
                window.vzPlayerBridge.onError(\(code), '\(escapedMsg)');
            } else if (window.vzPlayerBridge && typeof window.vzPlayerBridge.triggerError === 'function') {
                window.vzPlayerBridge.triggerError(\(code), '\(escapedMsg)');
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
    
    // MARK: - 处理来自 JS 的指令分发
    
    @discardableResult
    public func handleScriptMessage(method: String, paramsJson: String = "{}") -> String? {
        guard let player = player else { return nil }
        
        switch method {
        case "play", "Play":
            player.Play()
            return nil
        case "pause", "Pause":
            player.Pause()
            return nil
        case "resume", "Resume":
            player.Resume()
            return nil
        case "destroy", "Destroy":
            player.Destroy()
            return nil
        case "seek", "Seek":
            if let dict = parseJSON(paramsJson),
               let sec = dict["seconds"] as? Int64 ?? (dict["currentTime"] as? Int64) ?? (dict["currentTime"] as? Int).map(Int64.init) {
                player.Seek(sec)
            }
            return nil
        case "setCurrentTime", "set_currentTime":
            _ = player.set_currentTime(paramsJson)
            return nil
        case "getCurrentTime", "get_currentTime":
            return player.get_currentTime()
        case "getDuration", "get_duration":
            return player.get_duration()
        case "getPause", "get_pause":
            return player.get_pause()
        case "getVolume", "get_volume":
            return player.get_volume()
        case "setVolume", "set_volume":
            _ = player.set_volume(paramsJson)
            return nil
        case "getMuted", "get_muted":
            return player.get_muted()
        case "setMuted", "set_muted":
            _ = player.set_muted(paramsJson)
            return nil
        case "getVideoWidth", "get_videoWidth":
            return player.get_videoWidth()
        case "getVideoHeight", "get_videoHeight":
            return player.get_videoHeight()
        case "getLoop", "get_loop":
            return player.get_loop()
        case "setLoop", "set_loop":
            _ = player.set_loop(paramsJson)
            return nil
        case "getSpeed", "get_speed":
            return player.get_speed()
        case "setSpeed", "set_speed":
            _ = player.set_speed(paramsJson)
            return nil
        case "getBuffered", "get_buffered":
            return player.get_buffered()
        case "getCurrentSource", "get_currentsource":
            return player.get_currentsource()
        case "sendEvent", "SendEvent":
            if let dict = parseJSON(paramsJson), let eventName = dict["eventName"] as? String {
                let innerParams = dict["params"] as? [String: Any] ?? [:]
                let innerJson = (try? JSONSerialization.data(withJSONObject: innerParams))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                player.SendEvent(eventName, paramsJson: innerJson)
            }
            return nil
        case "switchSource":
            if let dict = parseJSON(paramsJson),
               let idx = dict["index"] as? Int ?? (dict["sourceIndex"] as? Int) {
                _ = player.switchSource(index: idx)
            }
            return nil
        default:
            return nil
        }
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
extension VZPlayerBridge: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "vzPlayerBridge",
              let dict = message.body as? [String: Any],
              let method = dict["method"] as? String else {
            return
        }
        let paramsJson = dict["paramsJson"] as? String ?? "{}"
        handleScriptMessage(method: method, paramsJson: paramsJson)
    }
}
#endif
