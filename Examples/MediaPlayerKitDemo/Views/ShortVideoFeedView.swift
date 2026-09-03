import SwiftUI
import MediaPlayerKit

/// 切换模式：切流（不同推流） vs 切内部地址（同推流的不同协议/编码源）
public enum FeedSwitchMode: String, CaseIterable {
    case stream = "切流模式"
    case source = "切内部地址"
}

public struct ShortVideoFeedView: View {
    @ObservedObject private var apiService = StreamAPIService.shared
    
    @State private var switchMode: FeedSwitchMode = .stream
    @State private var currentStreamIndex: Int = 0
    @State private var currentSourceIndex: Int = 0
    
    @State private var activePlayer: MediaPlayerController?
    @State private var playerState: PlayerState = .idle
    @State private var isPlaying: Bool = false
    @State private var isMuted: Bool = false
    @State private var startLatencyMS: Double = 0
    @State private var qosReport: PlayerQoSReport?
    @State private var errorMessage: String?
    @State private var isLoading: Bool = false
    
    public init() {}
    
    private var currentStream: NodeStreamInfo? {
        guard !apiService.streamList.isEmpty,
              currentStreamIndex >= 0,
              currentStreamIndex < apiService.streamList.count else {
            return nil
        }
        return apiService.streamList[currentStreamIndex]
    }
    
    private var currentSources: [PlayerSourceItem] {
        guard let stream = currentStream else { return [] }
        return apiService.sourcesCache[stream.streamid]?.allSources ?? []
    }
    
    private var currentSource: PlayerSourceItem? {
        let sources = currentSources
        guard !sources.isEmpty,
              currentSourceIndex >= 0,
              currentSourceIndex < sources.count else {
            return nil
        }
        return sources[currentSourceIndex]
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 1. 上半部分：自适应视频播放器 (占满剩余空间，上下滑动手势切流)
            ZStack {
                Color.black
                
                if let player = activePlayer {
                    PlayerViewRepresentable(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .onTapGesture {
                            togglePlayPause()
                        }
                } else {
                    Color.black
                }
                
                // 加载状态指示器
                if isLoading || playerState == .preparing || playerState == .buffering {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.4)
                        .background(Circle().fill(Color.black.opacity(0.5)).frame(width: 50, height: 50))
                }
                
                // 暂停状态浮标
                if !isPlaying && playerState != .idle && !isLoading {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.85))
                        .shadow(radius: 6)
                        .onTapGesture {
                            togglePlayPause()
                        }
                }
                
                // 错误信息覆盖提示
                if let err = errorMessage {
                    VStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.body)
                            .foregroundColor(.red)
                        Text(err)
                            .font(.caption2)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(6)
                    .padding(.horizontal, 20)
                }
                
                // 空流列表提示
                if apiService.streamList.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 32))
                            .foregroundColor(.orange)
                        Text("当前节点暂无活跃在线流")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        Text("请在「节点配置」检查域名或点击刷新")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                        Button(action: {
                            apiService.fetchStreamList { streams in
                                if !streams.isEmpty {
                                    currentStreamIndex = 0
                                    currentSourceIndex = 0
                                    playCurrentStreamAndSource()
                                }
                            }
                        }) {
                            HStack(spacing: 4) {
                                if apiService.isLoadingStreams {
                                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("拉取节点流")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // 自适应填满上半部分
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        if value.translation.height < -40 {
                            // 向上滑动 -> 下一个 (循环)
                            switchNext()
                        } else if value.translation.height > 40 {
                            // 向下滑动 -> 上一个 (循环)
                            switchPrevious()
                        }
                    }
            )
            
            // MARK: - 2. 下半部分：紧凑型控制与信息面板 (无需滚动，全可见，直观高效)
            VStack(spacing: 8) {
                // (1) 模式选择器与节点快捷切换
                HStack(spacing: 8) {
                    Picker("切换模式", selection: $switchMode) {
                        Text("切流 (\(currentStreamIndex + 1)/\(max(1, apiService.streamList.count)))").tag(FeedSwitchMode.stream)
                        Text("切内部地址 (\(currentSources.count > 0 ? "\(currentSourceIndex + 1)/\(currentSources.count)" : "0"))").tag(FeedSwitchMode.source)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    if !apiService.nodeItems.isEmpty {
                        Menu {
                            ForEach(apiService.nodeItems) { item in
                                Button(action: {
                                    apiService.setActiveNode(domain: item.domain)
                                    currentStreamIndex = 0
                                    currentSourceIndex = 0
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
                            HStack(spacing: 2) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 8))
                                Text(apiService.activeNodeItem?.remark.isEmpty == false ? apiService.activeNodeItem!.remark : apiService.activeNodeDomain)
                                    .font(.system(size: 9, weight: .bold))
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 7))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(5)
                        }
                    }
                }
                
                // (2) 融合式流信息与播放源卡片 (紧凑高密度展示)
                VStack(alignment: .leading, spacing: 3) {
                    // 第 1 行：流 ID + 播放源协议/编码/厂商标签
                    HStack(spacing: 6) {
                        Text("📡 \(currentStream?.streamid ?? "未选择流")")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if let source = currentSource {
                            Text(source.type.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(source.type.lowercased() == "flv" ? Color.orange : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(3)
                            
                            if !source.codecText.isEmpty {
                                Text(source.codecText)
                                    .font(.system(size: 8.5, weight: .medium))
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(3)
                            }
                            
                            if let v = source.vendor, !v.isEmpty {
                                Text(v.uppercased())
                                    .font(.system(size: 8.5))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 第 2 行：分辨率、帧率、码率、IP 归属地
                    if let stream = currentStream {
                        HStack(spacing: 6) {
                            if !stream.resolutionText.isEmpty {
                                Text(stream.resolutionText)
                                    .foregroundColor(.blue)
                            }
                            if !stream.fpsText.isEmpty {
                                Text(stream.fpsText)
                            }
                            if !stream.bitrateText.isEmpty {
                                Text(stream.bitrateText)
                                    .foregroundColor(.green)
                            }
                            if !stream.locationText.isEmpty {
                                Text(stream.locationText)
                                    .lineLimit(1)
                            }
                        }
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    }
                }
                .padding(6)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(6)
                
                // (3) 主控切换按钮条 (大尺寸按键，直接操作无阻碍)
                HStack(spacing: 20) {
                    Button(action: {
                        switchPrevious()
                    }) {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 34))
                            Text(switchMode == .stream ? "上一路流" : "上个地址")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(canSwitchPrevious ? .blue : .gray.opacity(0.4))
                    }
                    .disabled(!canSwitchPrevious)
                    
                    // 播放/暂停
                    Button(action: {
                        togglePlayPause()
                    }) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: {
                        switchNext()
                    }) {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 34))
                            Text(switchMode == .stream ? "下一路流" : "下个地址")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(canSwitchNext ? .blue : .gray.opacity(0.4))
                    }
                    .disabled(!canSwitchNext)
                    
                    // 静音切换
                    Button(action: {
                        isMuted.toggle()
                        activePlayer?.setMute(isMuted)
                    }) {
                        VStack(spacing: 2) {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 22))
                                .frame(height: 34)
                            Text(isMuted ? "静音" : "声音")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(isMuted ? .red : .primary)
                    }
                }
                
                // (4) 底部 QoS 实时指标极简胶囊
                if let qos = qosReport {
                    HStack(spacing: 8) {
                        Text("⚡️ 起播: \(String(format: "%.1f", qos.firstFrameDuration > 0 ? qos.firstFrameDuration : startLatencyMS)) ms")
                            .foregroundColor(.green)
                        Text("内核: \(qos.engineName)")
                            .foregroundColor(.primary)
                        Text("硬解: \(qos.isHardwareAccelerated ? "开启" : "关闭")")
                            .foregroundColor(.secondary)
                    }
                    .font(.system(size: 8.5, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .background(Color.secondary.opacity(0.03))
        }
        .onAppear {
            PlayerPoolManager.shared.warmUp()
            if apiService.hasCompleteConfig && apiService.streamList.isEmpty {
                apiService.fetchStreamList { streams in
                    if !streams.isEmpty {
                        currentStreamIndex = 0
                        currentSourceIndex = 0
                        playCurrentStreamAndSource()
                    }
                }
            } else if !apiService.streamList.isEmpty {
                playCurrentStreamAndSource()
            }
        }
        .onDisappear {
            if let player = activePlayer {
                PlayerPoolManager.shared.recyclePlayer(player)
                activePlayer = nil
            }
        }
    }
    
    private var canSwitchPrevious: Bool {
        if switchMode == .stream {
            return !apiService.streamList.isEmpty
        } else {
            return !currentSources.isEmpty
        }
    }
    
    private var canSwitchNext: Bool {
        if switchMode == .stream {
            return !apiService.streamList.isEmpty
        } else {
            return !currentSources.isEmpty
        }
    }
    
    // MARK: - 循环切换上一个
    private func switchPrevious() {
        if switchMode == .stream {
            guard !apiService.streamList.isEmpty else { return }
            let count = apiService.streamList.count
            currentStreamIndex = (currentStreamIndex - 1 + count) % count
            currentSourceIndex = 0
            playCurrentStreamAndSource()
        } else {
            let sources = currentSources
            guard !sources.isEmpty else { return }
            currentSourceIndex = (currentSourceIndex - 1 + sources.count) % sources.count
            playCurrentSourceItem()
        }
    }
    
    // MARK: - 循环切换下一个
    private func switchNext() {
        if switchMode == .stream {
            guard !apiService.streamList.isEmpty else { return }
            let count = apiService.streamList.count
            currentStreamIndex = (currentStreamIndex + 1) % count
            currentSourceIndex = 0
            playCurrentStreamAndSource()
        } else {
            let sources = currentSources
            guard !sources.isEmpty else { return }
            currentSourceIndex = (currentSourceIndex + 1) % sources.count
            playCurrentSourceItem()
        }
    }
    
    private func playCurrentStreamAndSource() {
        guard let stream = currentStream else { return }
        self.errorMessage = nil
        
        // 检查该流的播放源是否已缓存
        if let container = apiService.sourcesCache[stream.streamid], !container.allSources.isEmpty {
            self.currentSourceIndex = min(self.currentSourceIndex, container.allSources.count - 1)
            playCurrentSourceItem()
        } else {
            self.isLoading = true
            apiService.fetchPlayerSources(for: stream.streamid) { container in
                self.isLoading = false
                guard let container = container, !container.allSources.isEmpty else {
                    self.errorMessage = "该流暂无可用的播放地址"
                    return
                }
                self.currentSourceIndex = 0
                self.playCurrentSourceItem()
            }
        }
    }
    
    private func playCurrentSourceItem() {
        guard let source = currentSource else {
            self.errorMessage = "当前未选择有效播放地址"
            return
        }
        guard let url = URL(string: source.src) else {
            self.errorMessage = "无效的播放 URL"
            return
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        self.errorMessage = nil
        
        // 1. 回收旧播放器
        if let oldPlayer = activePlayer {
            PlayerPoolManager.shared.recyclePlayer(oldPlayer)
        }
        
        // 2. 从实例池获取预热播放器
        let newPlayer = PlayerPoolManager.shared.dequeuePlayer()
        newPlayer.setMute(isMuted)
        
        let coordinator = FeedPlayerCoordinator(
            onStateChange: { state in
                self.playerState = state
                self.isPlaying = (state == .playing)
                if state == .playing {
                    self.errorMessage = nil
                }
            },
            onQoSUpdate: {
                self.qosReport = newPlayer.currentQoSReport()
            },
            onError: { err in
                self.errorMessage = "播放出错: \(err.localizedDescription)"
                self.isPlaying = false
            }
        )
        newPlayer.delegate = coordinator
        
        self.activePlayer = newPlayer
        newPlayer.setMediaSource(url: url)
        newPlayer.play()
        self.isPlaying = true
        
        self.startLatencyMS = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
    }
    
    private func togglePlayPause() {
        guard let player = activePlayer else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }
}

// 代理中继器
final class FeedPlayerCoordinator: NSObject, MediaPlayerDelegate {
    var onStateChange: ((PlayerState) -> Void)?
    var onQoSUpdate: (() -> Void)?
    var onError: ((NSError) -> Void)?

    init(
        onStateChange: @escaping (PlayerState) -> Void,
        onQoSUpdate: @escaping () -> Void,
        onError: @escaping (NSError) -> Void
    ) {
        self.onStateChange = onStateChange
        self.onQoSUpdate = onQoSUpdate
        self.onError = onError
    }

    func player(_ player: MediaPlayerController, stateDidChange state: PlayerState) {
        DispatchQueue.main.async {
            self.onStateChange?(state)
            self.onQoSUpdate?()
        }
    }

    func player(_ player: MediaPlayerController, currentTime: TimeInterval, totalDuration: TimeInterval) {
        DispatchQueue.main.async { self.onQoSUpdate?() }
    }

    func playerDidRenderFirstFrame(_ player: MediaPlayerController) {
        DispatchQueue.main.async { self.onQoSUpdate?() }
    }
    
    func player(_ player: MediaPlayerController, didOccurError error: NSError) {
        DispatchQueue.main.async { self.onError?(error) }
    }
}
