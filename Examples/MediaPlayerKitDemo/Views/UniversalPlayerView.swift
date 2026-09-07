import SwiftUI
import MediaPlayerKit
#if canImport(UIKit)
import UIKit
#endif

public struct UniversalPlayerView: View {
    @ObservedObject private var apiService = StreamAPIService.shared
    
    @State private var customURLText: String = ""
    
    // MARK: - VZPlayer (IH5Player) 核心实例与渲染视图
    private let playerView = MediaPlayerView()
    @State private var vzPlayer: IH5Player?
    @State private var coordinator: VZH5PlayerCoordinator?
    
    @State private var isPlaying = false
    @State private var isBuffering = false
    @State private var currentPosition: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var bufferedText: String = "0"
    @State private var playbackRate: Float = 1.0
    @State private var isMuted = false
    @State private var showH5Monitor = true
    @State private var errorMessage: String?
    @State private var currentPlayingTitle: String = "待播放"
    @State private var currentSourceJSON: String = "{}"
    @State private var recentH5Events: [String] = []
    
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // MARK: - 1. 顶部节点状态指示条 (支持快捷切换节点)
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    if apiService.nodeItems.isEmpty {
                        Text("未添加节点，请前往「配置」页添加")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
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
                            HStack(spacing: 4) {
                                Text("当前节点: \(apiService.activeNodeItem?.displayText ?? apiService.activeNodeDomain)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(12)
                        }
                    }
                    
                    Spacer()
                    
                    if apiService.hasCompleteConfig {
                        Button(action: {
                            apiService.fetchStreamList()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.05))
                
                // MARK: - 2. 视频渲染窗口 (VZPlayerView)
                ZStack(alignment: .topTrailing) {
                    VZPlayerViewRepresentable(playerView: playerView)
                        .frame(height: 220)
                        .background(Color.black)
                    
                    // 状态加载指示器
                    if isBuffering {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    // 错误提示蒙层
                    if let err = errorMessage {
                        VStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.85))
                    }
                    
                    // 实时 H5 API 监控指示悬浮窗
                    if showH5Monitor {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("⚡️ IH5Player API 监控")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.yellow)
                                Spacer()
                                Text(currentPlayingTitle)
                                    .font(.system(size: 8))
                                    .foregroundColor(.green)
                                    .lineLimit(1)
                            }
                            Text("进度: \(vzPlayer?.get_currentTime() ?? "{}") | 时长: \(vzPlayer?.get_duration() ?? "{}")")
                            Text("音量: \(vzPlayer?.get_volume() ?? "{}") | 静音: \(vzPlayer?.get_muted() ?? "{}")")
                            Text("倍速: \(vzPlayer?.get_speed() ?? "{}") | 缓冲: \(vzPlayer?.get_buffered() ?? "{}")")
                            if !recentH5Events.isEmpty {
                                Text("事件: \(recentH5Events.suffix(3).joined(separator: " ➔ "))")
                                    .foregroundColor(.cyan)
                                    .lineLimit(1)
                            }
                        }
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(5)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(6)
                        .padding(6)
                    }
                }
                
                // MARK: - 3. 进度条与播放控制栏 (通过 IH5Player API 控制)
                VStack(spacing: 6) {
                    // 时间进度条
                    VStack(spacing: 2) {
                        Slider(value: $currentPosition, in: 0...max(1, duration)) { editing in
                            if !editing {
                                _ = vzPlayer?.set_currentTime("{\"currentTime\": \(Int(currentPosition))}")
                            }
                        }
                        .accentColor(.blue)
                        
                        HStack {
                            Text(timeString(currentPosition))
                            Spacer()
                            Text(isPlaying ? "🟢 播放中" : "⚪️ 已暂停")
                                .foregroundColor(isPlaying ? .green : .secondary)
                            Spacer()
                            Text(timeString(duration))
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    
                    // 控制按钮条 (对标 IH5Player play/pause/set_speed/set_muted/SendEvent)
                    HStack(spacing: 16) {
                        Button(action: {
                            let newPos = max(0, currentPosition - 10)
                            _ = vzPlayer?.set_currentTime("{\"currentTime\": \(Int(newPos))}")
                        }) {
                            Image(systemName: "gobackward.10")
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        
                        Button(action: {
                            if isPlaying {
                                vzPlayer?.pause()
                            } else {
                                vzPlayer?.play()
                            }
                        }) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.blue)
                        }
                        
                        Button(action: {
                            let newPos = min(duration, currentPosition + 10)
                            _ = vzPlayer?.set_currentTime("{\"currentTime\": \(Int(newPos))}")
                        }) {
                            Image(systemName: "goforward.10")
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        
                        // 主动切下一个源 (SendEvent NEXT_SOURCE)
                        Button(action: {
                            vzPlayer?.sendEvent("NEXT_SOURCE", paramsJson: "{}")
                            refreshH5State()
                        }) {
                            VStack(spacing: 1) {
                                Image(systemName: "arrow.triangle.swap")
                                    .font(.system(size: 14))
                                Text("下个源")
                                    .font(.system(size: 8))
                            }
                            .foregroundColor(.purple)
                        }
                        
                        Divider().frame(height: 18)
                        
                        // 倍速切换菜单 (set_speed)
                        Menu {
                            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                                Button("\(String(format: "%.2fx", rate))") {
                                    playbackRate = Float(rate)
                                    _ = vzPlayer?.set_speed("{\"speed\": \(rate)}")
                                    refreshH5State()
                                }
                            }
                        } label: {
                            Text("\(String(format: "%.2fx", playbackRate))")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(4)
                        }
                        
                        // 静音切换 (set_muted)
                        Button(action: {
                            isMuted.toggle()
                            _ = vzPlayer?.set_muted("{\"muted\": \(isMuted)}")
                            refreshH5State()
                        }) {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .foregroundColor(isMuted ? .red : .primary)
                        }
                        
                        // H5 监控悬浮窗开关
                        Button(action: {
                            showH5Monitor.toggle()
                        }) {
                            Image(systemName: showH5Monitor ? "gauge.with.needle.fill" : "gauge.with.needle")
                                .foregroundColor(showH5Monitor ? .yellow : .secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08))
                
                // MARK: - 4. 节点在线流列表区
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.green)
                        Text("节点实时在线流 (点击直接注入 VZPlayerSource)")
                            .font(.system(size: 12, weight: .bold))
                        
                        if !apiService.streamList.isEmpty {
                            Text("\(apiService.streamList.count) 条")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(6)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    
                    if apiService.isLoadingStreams {
                        HStack {
                            Spacer()
                            ProgressView("正在获取流列表...")
                                .font(.caption)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    } else if apiService.streamList.isEmpty {
                        Text("当前节点暂无活跃流，可在下方手动输入播放地址")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(apiService.streamList) { stream in
                                    Button(action: {
                                        playNodeStream(stream)
                                    }) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(stream.streamid)
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            
                                            HStack(spacing: 4) {
                                                if !stream.resolutionText.isEmpty {
                                                    Text(stream.resolutionText)
                                                        .font(.system(size: 8.5))
                                                        .foregroundColor(.blue)
                                                }
                                                if !stream.fpsText.isEmpty {
                                                    Text(stream.fpsText)
                                                        .font(.system(size: 8.5))
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                        .padding(6)
                                        .background(Color.secondary.opacity(0.08))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                        }
                    }
                }
                .padding(.vertical, 4)
                
                // MARK: - 5. 手动输入与自定义源测试
                VStack(alignment: .leading, spacing: 6) {
                    Text("自定义播放源测试 (支持 HLS / FLV / MP4)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                    
                    HStack {
                        TextField("输入播放 URL (如 https://...m3u8)", text: $customURLText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.system(size: 12))
                        
                        Button(action: {
                            playCustomURL(customURLText)
                        }) {
                            Text("播放")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .padding(.vertical, 6)
            }
        }
        .onAppear {
            setupVZPlayer()
        }
        .onDisappear {
            vzPlayer?.destroy()
        }
    }
    
    // MARK: - 初始化 VZPlayer 与 H5 事件监听
    
    private func setupVZPlayer() {
        guard vzPlayer == nil else { return }
        
        // 1. 初始化全局配置 (对标 export.Init)
        let initConfig = VZInitConfig()
        initConfig.userId = 10001
        initConfig.topicId = "topic_demo"
        initConfig.deviceInfo = "iOS MediaPlayerKit Demo"
        export.Init(initConfig, nil)
        
        // 2. 创建 IH5Player 门面对象 (对标 export.CreateVZPlayer)
        let player = export.CreateVZPlayer(playerView)
        
        // 3. 绑定 H5 事件监听器 (对标 IH5Player.H5EventListener)
        let coord = VZH5PlayerCoordinator(
            onEvent: { eventName in
                recentH5Events.append(eventName)
                if eventName == "play" || eventName == "playing" {
                    isPlaying = true
                    errorMessage = nil
                } else if eventName == "pause" {
                    isPlaying = false
                } else if eventName == "waiting" {
                    isBuffering = true
                } else if eventName == "canplaythrough" {
                    isBuffering = false
                } else if eventName == "ended" {
                    isPlaying = false
                }
                refreshH5State()
            },
            onError: { code, errMsg in
                errorMessage = "播放错误 [\(code)]: \(errMsg)"
                isPlaying = false
                isBuffering = false
            },
            onTimeUpdate: { curTime in
                currentPosition = TimeInterval(curTime)
            }
        )
        player.setOnH5EventListener(coord)
        
        self.vzPlayer = player
        self.coordinator = coord
    }
    
    private func refreshH5State() {
        guard let player = vzPlayer else { return }
        currentSourceJSON = player.get_currentsource()
        bufferedText = player.get_buffered()
    }
    
    // MARK: - 业务播放拉起 (注入 VZPlayerSource 多源)
    
    private func playNodeStream(_ stream: NodeStreamInfo) {
        currentPlayingTitle = stream.streamid
        errorMessage = nil
        
        apiService.fetchPlayerSources(for: stream.streamid) { container in
            guard let container = container, !container.allSources.isEmpty else {
                errorMessage = "未解析出该流的播放源"
                return
            }
            
            // 构造多播放源数组 (支持 HLS/FLV 多协议容错)
            let vzSources = container.allSources.enumerated().map { (index, item) -> VZPlayerSource in
                let source = VZPlayerSource(
                    url: item.src,
                    type: item.type.lowercased(),
                    tag: item.tag ?? "source_\(index)",
                    videoCodec: item.codec.contains("265") ? 2 : 1,
                    orderno: index + 1,
                    isLive: true,
                    ext: item.type.lowercased()
                )
                source.sourceIndex = index
                return source
            }
            
            // 调用 IH5Player API
            vzPlayer?.setSources(vzSources)
            vzPlayer?.play()
            refreshH5State()
        }
    }
    
    private func playCustomURL(_ urlStr: String) {
        guard !urlStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        currentPlayingTitle = "自定义源"
        errorMessage = nil
        
        let type = urlStr.lowercased().contains(".flv") ? VZPlayerSource.TYPE_FLV : VZPlayerSource.TYPE_HLS
        let source = VZPlayerSource(url: urlStr, type: type, isLive: true)
        
        vzPlayer?.setSources([source])
        vzPlayer?.play()
        refreshH5State()
    }
    
    private func timeString(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - H5 监听器代理协调器 (实现 VZH5EventListener)
final class VZH5PlayerCoordinator: NSObject, VZH5EventListener {
    private let onEventHandler: (String) -> Void
    private let onErrorHandler: (Int, String) -> Void
    private let onTimeUpdateHandler: (Int64) -> Void
    
    init(
        onEvent: @escaping (String) -> Void,
        onError: @escaping (Int, String) -> Void,
        onTimeUpdate: @escaping (Int64) -> Void
    ) {
        self.onEventHandler = onEvent
        self.onErrorHandler = onError
        self.onTimeUpdateHandler = onTimeUpdate
    }
    
    func onEvent(_ eventName: String) {
        DispatchQueue.main.async {
            self.onEventHandler(eventName)
        }
    }
    
    func onError(_ code: Int, errMsg: String) {
        DispatchQueue.main.async {
            self.onErrorHandler(code, errMsg)
        }
    }
    
    func onTimeUpdate(_ currentTime: Int64) {
        DispatchQueue.main.async {
            self.onTimeUpdateHandler(currentTime)
        }
    }
}
