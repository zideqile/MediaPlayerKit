import SwiftUI
import MediaPlayerKit
#if canImport(UIKit)
import UIKit
#endif

public struct UniversalPlayerView: View {
    @ObservedObject private var apiService = StreamAPIService.shared
    @StateObject private var viewModel = UniversalPlayerViewModel()
    @State private var customURLText: String = ""
    
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
                    VZPlayerViewRepresentable(playerView: viewModel.playerView)
                        .frame(height: 220)
                        .background(Color.black)
                    
                    // 状态加载指示器
                    if viewModel.isBuffering {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    // 错误提示蒙层
                    if let err = viewModel.errorMessage {
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
                    if viewModel.showH5Monitor {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("⚡️ IH5Player API 监控")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.yellow)
                                Spacer()
                                Text(viewModel.currentPlayingTitle)
                                    .font(.system(size: 8))
                                    .foregroundColor(.green)
                                    .lineLimit(1)
                            }
                            Text("进度: \(viewModel.vzPlayer?.get_currentTime() ?? "{}") | 时长: \(viewModel.vzPlayer?.get_duration() ?? "{}")")
                            Text("音量: \(viewModel.vzPlayer?.get_volume() ?? "{}") | 静音: \(viewModel.vzPlayer?.get_muted() ?? "{}")")
                            Text("倍速: \(viewModel.vzPlayer?.get_speed() ?? "{}") | 缓冲: \(viewModel.vzPlayer?.get_buffered() ?? "{}")")
                            if !viewModel.recentH5Events.isEmpty {
                                Text("事件: \(viewModel.recentH5Events.suffix(3).joined(separator: " ➔ "))")
                                    .foregroundColor(Color(red: 0.0, green: 0.8, blue: 0.9))
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
                        Slider(value: $viewModel.currentPosition, in: 0...max(1, viewModel.duration)) { editing in
                            if !editing {
                                _ = viewModel.vzPlayer?.set_currentTime("{\"currentTime\": \(Int(viewModel.currentPosition))}")
                            }
                        }
                        .accentColor(.blue)
                        
                        HStack {
                            Text(viewModel.timeString(viewModel.currentPosition))
                            Spacer()
                            Text(viewModel.isPlaying ? "🟢 播放中" : "⚪️ 已暂停")
                                .foregroundColor(viewModel.isPlaying ? .green : .secondary)
                            Spacer()
                            Text(viewModel.timeString(viewModel.duration))
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    
                    // 控制按钮条 (对标 IH5Player play/pause/set_speed/set_muted/SendEvent)
                    HStack(spacing: 16) {
                        Button(action: {
                            let newPos = max(0, viewModel.currentPosition - 10)
                            _ = viewModel.vzPlayer?.set_currentTime("{\"currentTime\": \(Int(newPos))}")
                        }) {
                            Image(systemName: "gobackward.10")
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        
                        Button(action: {
                            if viewModel.isPlaying {
                                viewModel.vzPlayer?.pause()
                            } else {
                                viewModel.vzPlayer?.play()
                            }
                        }) {
                            Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.blue)
                        }
                        
                        Button(action: {
                            let newPos = min(viewModel.duration, viewModel.currentPosition + 10)
                            _ = viewModel.vzPlayer?.set_currentTime("{\"currentTime\": \(Int(newPos))}")
                        }) {
                            Image(systemName: "goforward.10")
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        
                        // 主动切下一个源 (SendEvent NEXT_SOURCE)
                        Button(action: {
                            viewModel.vzPlayer?.SendEvent("NEXT_SOURCE", "{}")
                            viewModel.refreshH5State()
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
                                    viewModel.playbackRate = Float(rate)
                                    _ = viewModel.vzPlayer?.set_speed("{\"speed\": \(rate)}")
                                    viewModel.refreshH5State()
                                }
                            }
                        } label: {
                            Text("\(String(format: "%.2fx", viewModel.playbackRate))")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(4)
                        }
                        
                        // 静音切换 (set_muted)
                        Button(action: {
                            viewModel.isMuted.toggle()
                            _ = viewModel.vzPlayer?.set_muted("{\"muted\": \(viewModel.isMuted)}")
                            viewModel.refreshH5State()
                        }) {
                            Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .foregroundColor(viewModel.isMuted ? .red : .primary)
                        }
                        
                        // H5 监控悬浮窗开关
                        Button(action: {
                            viewModel.showH5Monitor.toggle()
                        }) {
                            Image(systemName: viewModel.showH5Monitor ? "gauge.with.needle.fill" : "gauge.with.needle")
                                .foregroundColor(viewModel.showH5Monitor ? .yellow : .secondary)
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
                                        viewModel.playNodeStream(stream, apiService: apiService)
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
                            viewModel.playCustomURL(customURLText)
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
            viewModel.setupVZPlayer()
        }
        .onDisappear {
            viewModel.teardown()
        }
    }
}

// MARK: - UniversalPlayerViewModel
final class UniversalPlayerViewModel: ObservableObject {
    let playerView = MediaPlayerView()
    @Published var vzPlayer: IH5Player?
    @Published var coordinator: VZH5PlayerCoordinator?
    
    @Published var isPlaying = false
    @Published var isBuffering = false
    @Published var currentPosition: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var bufferedText: String = "0"
    @Published var playbackRate: Float = 1.0
    @Published var isMuted = false
    @Published var showH5Monitor = true
    @Published var errorMessage: String?
    @Published var currentPlayingTitle: String = "待播放"
    @Published var currentSourceJSON: String = "{}"
    @Published var recentH5Events: [String] = []
    
    private var activeFetchRequestId: UUID?
    
    func setupVZPlayer() {
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
            onEvent: { [weak self] eventName in
                guard let self = self else { return }
                self.recentH5Events.append(eventName)
                if eventName == "play" || eventName == "playing" {
                    self.isPlaying = true
                    self.errorMessage = nil
                } else if eventName == "pause" {
                    self.isPlaying = false
                } else if eventName == "waiting" {
                    self.isBuffering = true
                } else if eventName == "canplaythrough" {
                    self.isBuffering = false
                } else if eventName == "ended" {
                    self.isPlaying = false
                }
                self.refreshH5State()
            },
            onError: { [weak self] code, errMsg in
                guard let self = self else { return }
                self.errorMessage = "播放错误 [\(code)]: \(errMsg)"
                self.isPlaying = false
                self.isBuffering = false
            },
            onTimeUpdate: { [weak self] curTime in
                guard let self = self else { return }
                self.currentPosition = TimeInterval(curTime)
                if self.duration == 0 {
                    self.refreshDuration()
                }
            }
        )
        player.SetOnH5EventListener(coord)
        
        self.vzPlayer = player
        self.coordinator = coord
    }
    
    func teardown() {
        vzPlayer?.destroy()
        vzPlayer = nil
        coordinator = nil
    }
    
    func refreshH5State() {
        guard let player = vzPlayer else { return }
        currentSourceJSON = player.get_currentsource()
        bufferedText = player.get_buffered()
        refreshDuration()
    }
    
    func refreshDuration() {
        guard let player = vzPlayer else { return }
        if let durData = player.get_duration().data(using: .utf8),
           let durDict = try? JSONSerialization.jsonObject(with: durData) as? [String: Any],
           let dur = (durDict["duration"] as? Double) ?? (durDict["duration"] as? Int64).map(Double.init),
           dur > 0 {
            self.duration = dur
        }
    }
    
    func playNodeStream(_ stream: NodeStreamInfo, apiService: StreamAPIService) {
        currentPlayingTitle = stream.streamid
        errorMessage = nil
        
        let requestId = UUID()
        self.activeFetchRequestId = requestId
        
        apiService.fetchPlayerSources(for: stream.streamid) { [weak self] container in
            guard let self = self, self.activeFetchRequestId == requestId else { return }
            guard let container = container, !container.allSources.isEmpty else {
                self.errorMessage = "未解析出该流的播放源"
                return
            }
            
            // 构造多播放源数组 (支持 HLS/FLV 多协议容错)
            let vzSources = container.allSources.enumerated().map { (index, item) -> VZPlayerSource in
                let source = VZPlayerSource(
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
            
            // 调用 IH5Player API
            self.vzPlayer?.setSources(vzSources)
            self.vzPlayer?.play()
            self.refreshH5State()
        }
    }
    
    func playCustomURL(_ urlStr: String) {
        guard !urlStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        currentPlayingTitle = "自定义源"
        errorMessage = nil
        
        let type = urlStr.lowercased().contains(".flv") ? VZPlayerSource.TYPE_FLV : VZPlayerSource.TYPE_HLS
        let source = VZPlayerSource(url: urlStr, type: type, isLive: true)
        
        vzPlayer?.setSources([source])
        vzPlayer?.play()
        refreshH5State()
    }
    
    func timeString(_ time: TimeInterval) -> String {
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
