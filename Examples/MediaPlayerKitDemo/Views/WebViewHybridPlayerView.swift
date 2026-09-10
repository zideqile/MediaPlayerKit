import SwiftUI
import MediaPlayerKit
#if canImport(WebKit)
import WebKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - H5 混合播放器静态资源定位器 (从独立资源包加载 index.html)
private func getHybridPlayerIndexURL() -> URL? {
    let candidateSubdirs = ["Resources/HybridPlayer", "HybridPlayer", ""]
    
    #if SWIFT_PACKAGE
    for subdir in candidateSubdirs {
        if let url = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: subdir.isEmpty ? nil : subdir) {
            return url
        }
    }
    #endif
    
    for subdir in candidateSubdirs {
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: subdir.isEmpty ? nil : subdir) {
            return url
        }
    }
    
    return nil
}

// MARK: - WKWebView 跨平台 Representable 封装
#if canImport(UIKit)
public struct HybridWKWebViewRepresentable: UIViewRepresentable {
    public let webView: WKWebView

    public init(webView: WKWebView) {
        self.webView = webView
    }

    public func makeUIView(context: Context) -> WKWebView {
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#elseif canImport(AppKit)
import AppKit
public struct HybridWKWebViewRepresentable: NSViewRepresentable {
    public let webView: WKWebView

    public init(webView: WKWebView) {
        self.webView = webView
    }

    public func makeNSView(context: Context) -> WKWebView {
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif

// MARK: - JSBridge 协调器与事件监听器 (全面支持节点在线流与流内多播放线路精准状态闭环)
final class PlayerJSBridgeCoordinator: NSObject, WKScriptMessageHandler, H5EventListener {
    weak var webView: WKWebView?
    weak var vzPlayer: IH5Player?
    private let apiService = StreamAPIService.shared
    
    // 当前正在播放的流 ID
    var currentPlayingStreamId: String = ""
    
    // 当前流解析出的所有子播放线路
    var currentStreamSources: [PlayerSource] = []
    
    // 当前正在播放的子源索引
    var currentSourceIndex: Int = 0
    
    // 当前流是否正在网络请求加载线路
    var isStreamLoading: Bool = false
    
    // 获取线路失败时的错误信息
    var streamFetchError: String? = nil
    
    // 当前底层内核状态: idle | preparing | playing | paused | buffering | ended | error
    var currentPlaybackState: String = "idle"
    
    // 异步防竞争请求 Token
    private var activeFetchRequestId: UUID?
    
    init(webView: WKWebView? = nil, vzPlayer: IH5Player?) {
        self.webView = webView
        self.vzPlayer = vzPlayer
        super.init()
    }
    
    // MARK: - WKScriptMessageHandler (拦截 H5 ➔ Native 指令)
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "vzPlayerBridge",
              let dict = message.body as? [String: Any],
              let method = dict["method"] as? String else {
            return
        }
        
        let paramsJson = dict["paramsJson"] as? String ?? "{}"
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let player = self.vzPlayer else { return }
            
            // Reuse SDK request/reply dispatch without replacing the Demo event listener.
            if let requestId = dict["requestId"] as? String {
                let bridge = PlayerBridge(player: nil)
                bridge.player = player
                PlayerBridge.reply(bridge.handleRequest(method: method, paramsJson: paramsJson, requestId: requestId), to: self.webView)
                self.syncPropertiesToH5()
                return
            }
            switch method {
            case "ready":
                // H5 DOM 与 JS 脚本初始化完毕握手，立即双向同步在线流与属性
                self.syncNodeStreamsToH5()
                self.syncPropertiesToH5()
            case "play", "Play":
                player.play()
            case "pause", "Pause":
                player.pause()
            case "setCurrentTime":
                _ = player.set_currentTime(paramsJson)
            case "setSpeed":
                _ = player.set_speed(paramsJson)
            case "setVolume":
                _ = player.set_volume(paramsJson)
            case "setMuted":
                _ = player.set_muted(paramsJson)
            case "switchStream":
                // 动态切节点推流：清空旧线路进入 loading 态并请求播放地址
                if let dict = self.parseJSON(paramsJson),
                   let streamId = dict["streamId"] as? String {
                    self.playNodeStream(streamId: streamId)
                }
            case "retryStream":
                // 重新请求当前流的播放地址
                if let dict = self.parseJSON(paramsJson),
                   let streamId = dict["streamId"] as? String {
                    self.playNodeStream(streamId: streamId, isRetry: true)
                } else if !self.currentPlayingStreamId.isEmpty {
                    self.playNodeStream(streamId: self.currentPlayingStreamId, isRetry: true)
                }
            case "switchSubSource":
                // 手动切换当前流内的指定播放线路 (严格校验 streamId)
                if let dict = self.parseJSON(paramsJson),
                   let idx = dict["index"] as? Int ?? (dict["sourceIndex"] as? Int) {
                    if let reqStreamId = dict["streamId"] as? String, !reqStreamId.isEmpty, reqStreamId != self.currentPlayingStreamId {
                        return // 忽略针对陈旧流 ID 的切线指令
                    }
                    guard idx >= 0, idx < self.currentStreamSources.count else { return }
                    self.currentSourceIndex = idx
                    self.currentPlaybackState = "preparing"
                    _ = player.switchSource(index: idx)
                    self.syncNodeStreamsToH5()
                    self.syncPropertiesToH5()
                }
            case "switchPrevSubSource":
                // 切换到上一条线路
                guard !self.currentStreamSources.isEmpty else { return }
                let prevIdx = (self.currentSourceIndex - 1 + self.currentStreamSources.count) % self.currentStreamSources.count
                self.currentSourceIndex = prevIdx
                self.currentPlaybackState = "preparing"
                _ = player.switchSource(index: prevIdx)
                self.syncNodeStreamsToH5()
                self.syncPropertiesToH5()
            case "switchNextSubSource":
                // 切换到下一条线路
                guard !self.currentStreamSources.isEmpty else { return }
                self.currentPlaybackState = "preparing"
                player.SendEvent("NEXT_SOURCE", "{}")
                self.syncNodeStreamsToH5()
                self.syncPropertiesToH5()

            case "switchPrevStream":
                // 切换到上一路推流
                let list = self.apiService.streamList
                guard !list.isEmpty else { return }
                if let currIdx = list.firstIndex(where: { $0.streamid == self.currentPlayingStreamId }) {
                    let prevIdx = (currIdx - 1 + list.count) % list.count
                    self.playNodeStream(streamId: list[prevIdx].streamid)
                } else if let first = list.first {
                    self.playNodeStream(streamId: first.streamid)
                }
            case "switchNextStream":
                // 切换到下一路推流
                let list = self.apiService.streamList
                guard !list.isEmpty else { return }
                if let currIdx = list.firstIndex(where: { $0.streamid == self.currentPlayingStreamId }) {
                    let nextIdx = (currIdx + 1) % list.count
                    self.playNodeStream(streamId: list[nextIdx].streamid)
                } else if let first = list.first {
                    self.playNodeStream(streamId: first.streamid)
                }
            case "refreshStreams":
                self.apiService.fetchStreamList { [weak self] _ in
                    self?.syncNodeStreamsToH5()
                }
            case "getProperties":
                self.syncNodeStreamsToH5()
                self.syncPropertiesToH5()
            default:
                break
            }
        }
    }
    
    /// 播放节点的在线流：自动请求 toolsapi 播放地址并构造成多源容错管线 (防异步竞争与数据串流)
    func playNodeStream(streamId: String, isRetry: Bool = false) {
        guard let player = vzPlayer else { return }
        
        // 1. 立即重置状态，防止旧流数据在请求期间被操作或反向覆盖
        self.currentPlayingStreamId = streamId
        self.currentStreamSources = []
        self.currentSourceIndex = 0
        self.isStreamLoading = true
        self.streamFetchError = nil
        self.currentPlaybackState = "preparing"
        
        let requestId = UUID()
        self.activeFetchRequestId = requestId
        
        // 2. 立即向 H5 发送加载状态与空线路
        self.syncNodeStreamsToH5()
        
        apiService.fetchPlayerSources(for: streamId) { [weak self] container in
            guard let self = self, self.activeFetchRequestId == requestId else { return }
            self.isStreamLoading = false
            
            if let container = container, !container.allSources.isEmpty {
                let vzSources = container.allSources.enumerated().map { (index, item) -> PlayerSource in
                    let source = PlayerSource(
                        url: item.src,
                        type: item.type.lowercased(),
                        tag: item.tag ?? "source_\(index)",
                        videoCodec: item.videoCodec ?? (item.codecText.contains("265") ? 4 : 2),
                        orderno: index + 1,
                        isLive: true,
                        ext: item.type.lowercased()
                    )
                    source.sourceIndex = index
                    return source
                }
                self.currentStreamSources = vzSources
                self.currentSourceIndex = 0
                self.streamFetchError = nil
                player.setSources(vzSources)
                player.play()
            } else {
                self.currentStreamSources = []
                self.currentSourceIndex = 0
                self.streamFetchError = self.apiService.sourcesError ?? "未查询到当前流的可用播放地址"
            }
            self.syncNodeStreamsToH5()
            self.syncPropertiesToH5()
        }
    }
    
    private func parseJSON(_ jsonStr: String) -> [String: Any]? {
        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }
    
    /// 将节点最新在线流与当前流的子播放线路实时同步给 H5
    func syncNodeStreamsToH5() {
        guard let webView = webView else { return }
        
        let streamsArray: [[String: Any]] = apiService.streamList.map { s in
            return [
                "streamid": s.streamid,
                "resolution": s.resolutionText,
                "fps": s.fpsText,
                "bitrate": s.bitrateText,
                "location": s.locationText
            ]
        }
        
        let subSourcesArray: [[String: Any]] = currentStreamSources.enumerated().map { (index, s) in
            return [
                "index": index,
                "tag": s.tag,
                "type": s.type,
                "videoCodec": s.videoCodec,
                "codecText": s.videoCodec == 4 ? "H.265" : "H.264",
                "url": s.url,
                "isLive": s.isLive
            ]
        }
        
        if let player = vzPlayer,
           let srcData = player.get_currentsource().data(using: .utf8),
           let srcDict = try? JSONSerialization.jsonObject(with: srcData) as? [String: Any],
           let activeIdx = srcDict["sourceIndex"] as? Int {
            self.currentSourceIndex = activeIdx
        }
        
        var payload: [String: Any] = [
            "activeNodeDomain": apiService.activeNodeDomain,
            "activeNodeRemark": apiService.activeNodeItem?.remark ?? apiService.activeNodeDomain,
            "currentStreamId": currentPlayingStreamId,
            "isStreamLoading": isStreamLoading,
            "playbackState": currentPlaybackState,
            "streams": streamsArray,
            "subSources": subSourcesArray,
            "currentSourceIndex": currentSourceIndex
        ]
        
        if let err = streamFetchError {
            payload["streamFetchError"] = err
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let jsonStr = String(data: data, encoding: .utf8) {
            let script = "if (window.vzBridgeUpdateStreamList) { window.vzBridgeUpdateStreamList(\(jsonStr)); }"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
    
    func syncPropertiesToH5() {
        guard let player = vzPlayer, let webView = webView else { return }
        let curTimeJson = player.get_currentTime()
        let durJson = player.get_duration()
        let speedJson = player.get_speed()
        let volJson = player.get_volume()
        let mutedJson = player.get_muted()
        let widthJson = player.get_videoWidth()
        let heightJson = player.get_videoHeight()
        let srcJson = player.get_currentsource()
        
        let script = """
        (function() {
            try {
                const curTime = \(curTimeJson).currentTime || 0;
                const dur = \(durJson).duration || 0;
                const spd = \(speedJson).speed || 1.0;
                const vol = \(volJson).volume || 1.0;
                const mut = \(mutedJson).muted || false;
                const w = \(widthJson).videoWidth || 0;
                const h = \(heightJson).videoHeight || 0;
                const src = \(srcJson.isEmpty ? "{}" : srcJson);
                if (window.vzBridgeUpdateProperties) {
                    window.vzBridgeUpdateProperties({
                        currentTime: curTime,
                        duration: dur,
                        speed: spd,
                        volume: vol,
                        muted: mut,
                        videoWidth: w,
                        videoHeight: h,
                        currentSource: src
                    });
                }
            } catch(e) {
                console.error(e);
            }
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    
    // MARK: - VZH5EventListener (Native ➔ H5 实时广播)
    func onEvent(_ eventName: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let webView = self.webView else { return }
            
            if eventName == "playing" || eventName == "canplaythrough" {
                self.currentPlaybackState = "playing"
            } else if eventName == "pause" {
                self.currentPlaybackState = "paused"
            } else if eventName == "waiting" {
                self.currentPlaybackState = "buffering"
            } else if eventName == "ended" {
                self.currentPlaybackState = "ended"
            }
            
            let script = "if (window.vzBridgeReceiveEvent) { window.vzBridgeReceiveEvent('\(eventName)'); }"
            webView.evaluateJavaScript(script, completionHandler: nil)
            
            if eventName == "PlayerWARN" || eventName == "playing" || eventName == "canplaythrough" {
                self.syncNodeStreamsToH5()
                self.syncPropertiesToH5()
            }
        }
    }
    
    func onTimeUpdate(_ currentTime: Int64) {
        DispatchQueue.main.async { [weak self] in
            guard let webView = self?.webView else { return }
            let script = "if (window.vzBridgeReceiveTimeUpdate) { window.vzBridgeReceiveTimeUpdate(\(currentTime)); }"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
    
    func onError(_ code: Int, errMsg: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let webView = self.webView else { return }
            self.currentPlaybackState = "error"
            let safeMsg = errMsg.replacingOccurrences(of: "'", with: "\\'")
            let script = "if (window.vzBridgeReceiveError) { window.vzBridgeReceiveError(\(code), '\(safeMsg)'); }"
            webView.evaluateJavaScript(script, completionHandler: nil)
            self.syncNodeStreamsToH5()
        }
    }
}

// MARK: - H5 混合播放持久化 ViewModel (彻底解决渲染视图与播放器生命周期脱节)
final class HybridPlayerViewModel: ObservableObject {
    let playerView = MediaPlayerView()
    @Published var vzPlayer: IH5Player?
    @Published var coordinator: PlayerJSBridgeCoordinator?
    @Published var webView: WKWebView?
    
    func setup(apiService: StreamAPIService) {
        guard vzPlayer == nil else { return }
        
        // 1. 初始化全局配置与创建 IH5Player 实例
        StreamAPIService.shared.configureLogServer(userId: 10003, topicId: "topic_webview_hybrid", deviceInfo: "iOS MediaPlayerKit Demo")
        let player = export.CreateVZPlayer(playerView)
        self.vzPlayer = player
        
        // 2. 初始化 WKUserContentController 与 WKWebViewConfiguration
        let userController = WKUserContentController()
        do {
            try PlayerBridge.installJavaScript(in: userController)
        } catch {
            Logger.logE("JS bridge installation failed:", error.localizedDescription, typeName: "WebViewHybridPlayerView")
        }
        let config = WKWebViewConfiguration()
        config.userContentController = userController
        
        let coord = PlayerJSBridgeCoordinator(webView: nil, vzPlayer: player)
        self.coordinator = coord
        
        // 注册 JSBridge 消息监听
        userController.add(coord, name: "vzPlayerBridge")
        
        let wv = WKWebView(frame: .zero, configuration: config)
        coord.webView = wv
        self.webView = wv
        
        // 注册播放器事件监听器 (对标 Android SetOnH5EventListener)
        player.SetOnH5EventListener(coord)
        
        // 3. 加载 H5 控制台页面 (从独立资源包加载 index.html)
        if let htmlURL = getHybridPlayerIndexURL() {
            let directoryURL = htmlURL.deletingLastPathComponent()
            wv.loadFileURL(htmlURL, allowingReadAccessTo: directoryURL)
        } else {
            print("[HybridPlayer] ⚠️ 未在 Bundle 中找到 index.html 静态资源文件")
        }
        
        // 4. 起播节点的首个流 (如有)
        if let firstStream = apiService.streamList.first {
            coord.playNodeStream(streamId: firstStream.streamid)
        } else if apiService.hasCompleteConfig {
            apiService.fetchStreamList { streams in
                if let first = streams.first {
                    coord.playNodeStream(streamId: first.streamid)
                } else {
                    coord.syncNodeStreamsToH5()
                }
            }
        }
    }
    
    func teardown() {
        if let userContentController = webView?.configuration.userContentController {
            userContentController.removeScriptMessageHandler(forName: "vzPlayerBridge")
        }
        vzPlayer?.destroy()
        vzPlayer = nil
        coordinator = nil
        webView = nil
    }
}

// MARK: - H5 混合播放演示主视图 (WebViewHybridPlayerView)
public struct WebViewHybridPlayerView: View {
    @ObservedObject private var apiService = StreamAPIService.shared
    @StateObject private var viewModel = HybridPlayerViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 1. 顶部原生视频渲染窗口 (PlayerView)
            ZStack(alignment: .topLeading) {
                PlayerViewRepresentable(playerView: viewModel.playerView)
                    .frame(height: 220)
                    .background(Color.black)
                
                // 顶部状态提示条与快捷节点菜单
                HStack {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Text("🖥 iOS 原生 Metal 渲染层")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(6)
                    
                    Spacer()
                    
                    if !apiService.nodeItems.isEmpty {
                        Menu {
                            ForEach(apiService.nodeItems) { item in
                                Button(action: {
                                    apiService.setActiveNode(domain: item.domain)
                                }) {
                                    HStack {
                                        Text(item.displayText)
                                        if apiService.activeNodeDomain == item.domain {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 9))
                                Text(apiService.activeNodeItem?.remark.isEmpty == false ? apiService.activeNodeItem!.remark : apiService.activeNodeDomain)
                                    .font(.system(size: 9.5, weight: .bold))
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 7.5))
                            }
                            .foregroundColor(Color(red: 0.0, green: 0.8, blue: 0.9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.75))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding(6)
            }
            
            Divider()
            
            // MARK: - 2. 下方 WKWebView (承载现代化底部导航 H5 控制台与 JSBridge)
            if let wv = viewModel.webView {
                HybridWKWebViewRepresentable(webView: wv)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("正在加载 H5 容器与 JSBridge...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            viewModel.setup(apiService: apiService)
            if apiService.hasCompleteConfig && apiService.streamList.isEmpty {
                apiService.fetchStreamList { _ in
                    viewModel.coordinator?.syncNodeStreamsToH5()
                }
            }
        }
        .onReceive(apiService.$streamList) { _ in
            viewModel.coordinator?.syncNodeStreamsToH5()
        }
        .onDisappear {
            viewModel.teardown()
        }
    }
}
