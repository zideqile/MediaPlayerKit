import SwiftUI
import MediaPlayerKit
#if canImport(WebKit)
import WebKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - HTML 嵌入式 H5 播放控制器页面模板
private let hybridPlayerHTML: String = """
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>IH5Player Web Console</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
        body { background-color: #121214; color: #E4E4E7; padding: 12px; font-size: 13px; }
        
        .card { background: #1C1C20; border-radius: 12px; padding: 12px; margin-bottom: 12px; border: 1px solid #27272A; }
        .title { font-size: 12px; font-weight: 700; color: #A1A1AA; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 8px; display: flex; align-items: center; justify-content: space-between; }
        .badge { background: #2563EB; color: #FFFFFF; font-size: 10px; padding: 2px 6px; border-radius: 4px; font-weight: 600; }
        
        .btn-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 6px; margin-bottom: 8px; }
        .btn { background: #27272A; color: #FAFAFA; border: none; border-radius: 8px; padding: 8px 4px; font-size: 12px; font-weight: 500; cursor: pointer; text-align: center; transition: all 0.15s ease; }
        .btn:active { background: #3B82F6; transform: scale(0.97); }
        .btn-primary { background: #2563EB; color: #FFFFFF; font-weight: 600; }
        .btn-accent { background: #059669; color: #FFFFFF; }
        .btn-warn { background: #D97706; color: #FFFFFF; }
        
        .slider-row { display: flex; align-items: center; justify-content: space-between; gap: 8px; margin: 6px 0; font-size: 12px; }
        .slider-row input[type=range] { flex: 1; accent-color: #3B82F6; height: 4px; }
        
        .stats-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 6px; font-size: 11px; }
        .stat-item { background: #27272A; padding: 6px 8px; border-radius: 6px; }
        .stat-label { color: #A1A1AA; font-size: 10px; margin-bottom: 2px; }
        .stat-val { font-family: ui-monospace, SFMono-Regular, monospace; font-weight: 600; color: #60A5FA; word-break: break-all; }
        
        .log-box { background: #09090B; border-radius: 8px; padding: 8px; max-height: 140px; overflow-y: auto; font-family: ui-monospace, SFMono-Regular, monospace; font-size: 10.5px; border: 1px solid #27272A; }
        .log-item { margin-bottom: 4px; line-height: 1.3; }
        .log-time { color: #71717A; margin-right: 4px; }
        .log-event { color: #34D399; font-weight: 600; }
        .log-error { color: #F87171; font-weight: 600; }
        .log-info { color: #60A5FA; }
    </style>
</head>
<body>

    <!-- 1. H5 播放控制器 -->
    <div class="card">
        <div class="title">
            <span>⚡️ H5 ➔ Native 控制指令 (JSBridge)</span>
            <span class="badge">W3C HTML5 API</span>
        </div>
        
        <div class="btn-grid">
            <button class="btn btn-primary" onclick="sendCmd('play')">▶️ 播放</button>
            <button class="btn btn-primary" onclick="sendCmd('pause')">⏸ 暂停</button>
            <button class="btn" onclick="seekOffset(-10)">⏪ -10s</button>
            <button class="btn" onclick="seekOffset(10)">⏩ +10s</button>
        </div>
        
        <div class="btn-grid">
            <button class="btn" onclick="setSpeed(1.0)">1.0x</button>
            <button class="btn" onclick="setSpeed(1.25)">1.25x</button>
            <button class="btn" onclick="setSpeed(1.5)">1.5x</button>
            <button class="btn" onclick="setSpeed(2.0)">2.0x</button>
        </div>

        <div class="btn-grid">
            <button class="btn btn-accent" onclick="toggleMute()">🔇 静音开关</button>
            <button class="btn btn-warn" onclick="switchSource('vod')">🎬 换回放源</button>
            <button class="btn btn-warn" onclick="switchSource('live')">📡 换直播源</button>
            <button class="btn" onclick="sendCmd('getProperties')">🔄 刷新属性</button>
        </div>

        <!-- 音量调节滑块 -->
        <div class="slider-row">
            <span>🔊 音量:</span>
            <input type="range" id="volumeSlider" min="0" max="100" value="100" oninput="onVolumeChange(this.value)">
            <span id="volumeText" style="min-width: 35px; text-align: right;">100%</span>
        </div>
        
        <!-- 进度调节滑块 -->
        <div class="slider-row">
            <span>⏱ 进度:</span>
            <input type="range" id="seekSlider" min="0" max="100" value="0" onchange="onSeekChange(this.value)">
            <span id="timeText" style="min-width: 65px; text-align: right;">00:00</span>
        </div>
    </div>

    <!-- 2. H5 实时属性读取指标 -->
    <div class="card">
        <div class="title">
            <span>📊 IH5Player 属性读取 (JSON Protocol)</span>
            <span id="liveStatusBadge" class="badge" style="background: #059669;">待机</span>
        </div>
        
        <div class="stats-grid">
            <div class="stat-item">
                <div class="stat-label">currentTime (进度)</div>
                <div class="stat-val" id="statCurrentTime">0s</div>
            </div>
            <div class="stat-item">
                <div class="stat-label">duration (时长)</div>
                <div class="stat-val" id="statDuration">0s</div>
            </div>
            <div class="stat-item">
                <div class="stat-label">speed (倍速)</div>
                <div class="stat-val" id="statSpeed">1.0x</div>
            </div>
            <div class="stat-item">
                <div class="stat-label">volume / muted</div>
                <div class="stat-val" id="statVolume">1.0 / false</div>
            </div>
            <div class="stat-item" style="grid-column: span 2;">
                <div class="stat-label">currentSource (生效播放源)</div>
                <div class="stat-val" id="statSource" style="font-size: 9.5px;">-</div>
            </div>
        </div>
    </div>

    <!-- 3. Native ➔ H5 实时事件流日志 -->
    <div class="card">
        <div class="title">
            <span>📡 Native ➔ H5 事件流 (VZH5EventListener)</span>
            <button class="btn" style="padding: 2px 6px; font-size: 10px;" onclick="clearLogs()">清空</button>
        </div>
        <div class="log-box" id="logBox">
            <div class="log-item"><span class="log-time">[Init]</span><span class="log-info">JSBridge 准备就绪，等待原生播放器事件...</span></div>
        </div>
    </div>

    <script>
        let currentPosSec = 0;
        let totalDurationSec = 0;
        let isMutedState = false;

        function log(type, msg) {
            const box = document.getElementById('logBox');
            const item = document.createElement('div');
            item.className = 'log-item';
            const now = new Date();
            const timeStr = now.toTimeString().split(' ')[0] + '.' + String(now.getMilliseconds()).padStart(3, '0');
            
            let typeHtml = `<span class="log-info">[${type}]</span>`;
            if (type === 'Event') typeHtml = `<span class="log-event">[Event]</span>`;
            if (type === 'Error') typeHtml = `<span class="log-error">[Error]</span>`;
            
            item.innerHTML = `<span class="log-time">${timeStr}</span>${typeHtml} ${msg}`;
            box.appendChild(item);
            box.scrollTop = box.scrollHeight;
        }

        function clearLogs() {
            document.getElementById('logBox').innerHTML = '';
        }

        // 发送 JSBridge 指令给 Native
        function sendCmd(method, paramsJson = '{}') {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vzPlayerBridge) {
                window.webkit.messageHandlers.vzPlayerBridge.postMessage({
                    method: method,
                    paramsJson: paramsJson
                });
                log('H5➔Native', `调用 ${method} 参数: ${paramsJson}`);
            } else {
                log('Error', '未检测到 vzPlayerBridge JSBridge 容器');
            }
        }

        function seekOffset(deltaSec) {
            const target = Math.max(0, currentPosSec + deltaSec);
            sendCmd('setCurrentTime', JSON.stringify({ currentTime: target }));
        }

        function onSeekChange(percent) {
            if (totalDurationSec > 0) {
                const target = Math.floor(totalDurationSec * (percent / 100));
                sendCmd('setCurrentTime', JSON.stringify({ currentTime: target }));
            }
        }

        function setSpeed(speedVal) {
            sendCmd('setSpeed', JSON.stringify({ speed: speedVal }));
        }

        function toggleMute() {
            isMutedState = !isMutedState;
            sendCmd('setMuted', JSON.stringify({ muted: isMutedState }));
        }

        function onVolumeChange(val) {
            document.getElementById('volumeText').innerText = val + '%';
            const vol = parseFloat(val) / 100.0;
            sendCmd('setVolume', JSON.stringify({ volume: vol }));
        }

        function switchSource(type) {
            sendCmd('switchSource', JSON.stringify({ sourceType: type }));
        }

        // ================= Native 回调注入方法 =================

        // 1. 原生播放器生命周期事件通知
        window.vzBridgeReceiveEvent = function(eventName) {
            log('Event', `触发原生事件: <b>${eventName}</b>`);
            const badge = document.getElementById('liveStatusBadge');
            if (eventName === 'playing' || eventName === 'play') {
                badge.innerText = '播放中';
                badge.style.background = '#059669';
            } else if (eventName === 'pause') {
                badge.innerText = '已暂停';
                badge.style.background = '#6B7280';
            } else if (eventName === 'waiting') {
                badge.innerText = '缓冲中...';
                badge.style.background = '#D97706';
            } else if (eventName === 'ended') {
                badge.innerText = '播放结束';
                badge.style.background = '#4B5563';
            }
            sendCmd('getProperties');
        };

        // 2. 原生进度定时心跳 (500ms)
        window.vzBridgeReceiveTimeUpdate = function(currentTimeSec) {
            currentPosSec = currentTimeSec;
            document.getElementById('statCurrentTime').innerText = currentTimeSec + 's';
            
            if (totalDurationSec > 0) {
                const percent = Math.min(100, Math.floor((currentPosSec / totalDurationSec) * 100));
                document.getElementById('seekSlider').value = percent;
                document.getElementById('timeText').innerText = formatTime(currentPosSec) + ' / ' + formatTime(totalDurationSec);
            } else {
                document.getElementById('timeText').innerText = formatTime(currentPosSec);
            }
        };

        // 3. 原生严重错误通知
        window.vzBridgeReceiveError = function(code, errMsg) {
            log('Error', `播放错误 code=${code} msg=${errMsg}`);
            const badge = document.getElementById('liveStatusBadge');
            badge.innerText = '播放异常';
            badge.style.background = '#DC2626';
        };

        // 4. 属性更新回传
        window.vzBridgeUpdateProperties = function(props) {
            try {
                if (props.duration !== undefined) {
                    totalDurationSec = props.duration;
                    document.getElementById('statDuration').innerText = props.duration + 's';
                }
                if (props.speed !== undefined) {
                    document.getElementById('statSpeed').innerText = props.speed + 'x';
                }
                if (props.volume !== undefined || props.muted !== undefined) {
                    document.getElementById('statVolume').innerText = (props.volume ?? 1.0) + ' / ' + (props.muted ? '静音' : '正常');
                    isMutedState = props.muted ?? false;
                }
                if (props.currentSource) {
                    document.getElementById('statSource').innerText = props.currentSource.url || JSON.stringify(props.currentSource);
                }
            } catch(e) {
                console.error(e);
            }
        };

        function formatTime(sec) {
            const m = Math.floor(sec / 60);
            const s = Math.floor(sec % 60);
            return String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
        }
    </script>
</body>
</html>
"""

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

// MARK: - JSBridge 协调器与事件监听器
final class VZPlayerJSBridgeCoordinator: NSObject, WKScriptMessageHandler, VZH5EventListener {
    weak var webView: WKWebView?
    weak var vzPlayer: IH5Player?
    
    // 常用播放源
    private let vodSources: [VZPlayerSource] = [
        VZPlayerSource(url: "https://vplayerctrl-dev.weizan.cn/girl.mp4", type: "hls", tag: "mp4_source", videoCodec: 2, orderno: 1, isLive: false, ext: "mp4"),
        VZPlayerSource(url: "https://p8.vzan.com/509306325/623870780773300121/live.m3u8", type: "hls", tag: "m3u8_source", videoCodec: 2, orderno: 2, isLive: false, ext: "m3u8")
    ]
    
    private let liveSources: [VZPlayerSource] = [
        VZPlayerSource(url: "https://p8.vzan.com/509306325/623870780773300121/live.m3u8", type: "hls", tag: "live_hls", videoCodec: 2, orderno: 1, isLive: true, ext: "m3u8"),
        VZPlayerSource(url: "https://p2.vzan.com/teststream40/teststream40/live.m3u8", type: "hls", tag: "live_backup", videoCodec: 2, orderno: 2, isLive: true, ext: "m3u8")
    ]
    
    init(webView: WKWebView, vzPlayer: IH5Player?) {
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
            
            switch method {
            case "play":
                player.play()
            case "pause":
                player.pause()
            case "setCurrentTime":
                _ = player.set_currentTime(paramsJson)
            case "setSpeed":
                _ = player.set_speed(paramsJson)
            case "setVolume":
                _ = player.set_volume(paramsJson)
            case "setMuted":
                _ = player.set_muted(paramsJson)
            case "switchSource":
                if paramsJson.contains("vod") {
                    player.setSources(self.vodSources)
                } else {
                    player.setSources(self.liveSources)
                }
                player.play()
            case "getProperties":
                self.syncPropertiesToH5()
            default:
                break
            }
        }
    }
    
    private func syncPropertiesToH5() {
        guard let player = vzPlayer, let webView = webView else { return }
        let curTimeJson = player.get_currentTime()
        let durJson = player.get_duration()
        let speedJson = player.get_speed()
        let volJson = player.get_volume()
        let mutedJson = player.get_muted()
        let srcJson = player.get_currentsource()
        
        // 组装聚合 JSON 发送给 H5
        let script = """
        (function() {
            try {
                const curTime = \(curTimeJson).currentTime || 0;
                const dur = \(durJson).duration || 0;
                const spd = \(speedJson).speed || 1.0;
                const vol = \(volJson).volume || 1.0;
                const mut = \(mutedJson).muted || false;
                const src = \(srcJson.isEmpty ? "{}" : srcJson);
                if (window.vzBridgeUpdateProperties) {
                    window.vzBridgeUpdateProperties({
                        currentTime: curTime,
                        duration: dur,
                        speed: spd,
                        volume: vol,
                        muted: mut,
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
            guard let webView = self?.webView else { return }
            let script = "if (window.vzBridgeReceiveEvent) { window.vzBridgeReceiveEvent('\(eventName)'); }"
            webView.evaluateJavaScript(script, completionHandler: nil)
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
            guard let webView = self?.webView else { return }
            let safeMsg = errMsg.replacingOccurrences(of: "'", with: "\\'")
            let script = "if (window.vzBridgeReceiveError) { window.vzBridgeReceiveError(\(code), '\(safeMsg)'); }"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}

// MARK: - H5 混合播放演示主视图 (WebViewHybridPlayerView)
public struct WebViewHybridPlayerView: View {
    private let playerView = MediaPlayerView()
    @State private var vzPlayer: IH5Player?
    @State private var coordinator: VZPlayerJSBridgeCoordinator?
    @State private var webView: WKWebView?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 1. 顶部原生视频渲染窗口 (VZPlayerView)
            ZStack(alignment: .topLeading) {
                VZPlayerViewRepresentable(playerView: playerView)
                    .frame(height: 220)
                    .background(Color.black)
                
                // 顶部标识
                HStack {
                    Text("🖥 Native 渲染窗口 (Metal / AVPlayer)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.65))
                        .cornerRadius(6)
                    Spacer()
                }
                .padding(8)
            }
            
            Divider()
            
            // MARK: - 2. 下方 WKWebView (承载 H5 控制台与 JSBridge 实时交互)
            if let wv = webView {
                HybridWKWebViewRepresentable(webView: wv)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    ProgressView()
                    Text("正在装载 H5 容器与 JSBridge...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            setupHybridPlayer()
        }
        .onDisappear {
            vzPlayer?.destroy()
        }
    }

    private func setupHybridPlayer() {
        guard vzPlayer == nil else { return }

        // 1. 创建 IH5Player 实例
        let player = export.CreateVZPlayer(playerView: playerView)
        self.vzPlayer = player

        // 2. 初始化 WKWebView 与 JSBridge 注入
        let config = WKWebViewConfiguration()
        let userController = WKUserContentController()
        
        let wv = WKWebView(frame: .zero, configuration: config)
        self.webView = wv

        let coord = VZPlayerJSBridgeCoordinator(webView: wv, vzPlayer: player)
        self.coordinator = coord
        
        // 注册 JSBridge 消息监听
        userController.add(coord, name: "vzPlayerBridge")
        config.userContentController = userController
        
        // 注册播放器事件监听器
        player.setOnH5EventListener(coord)

        // 默认载入测试播放源
        let initialSource = VZPlayerSource(
            url: "https://vplayerctrl-dev.weizan.cn/girl.mp4",
            type: "hls",
            tag: "hybrid_default",
            videoCodec: 2,
            orderno: 1,
            isLive: false,
            ext: "mp4"
        )
        player.setSources([initialSource])

        // 3. 加载 H5 控制台页面
        wv.loadHTMLString(hybridPlayerHTML, baseURL: nil)
    }
}
