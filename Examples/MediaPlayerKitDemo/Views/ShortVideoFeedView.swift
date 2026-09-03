import SwiftUI
import MediaPlayerKit
#if canImport(UIKit)
import UIKit
#endif

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
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // MARK: - 1. 上半部分：独立视频播放区域 (仿抖音无遮挡沉浸画面)
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
                    
                    // 加载状态
                    if isLoading || playerState == .preparing || playerState == .buffering {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                            .background(Circle().fill(Color.black.opacity(0.5)).frame(width: 60, height: 60))
                    }
                    
                    // 暂停状态居中图标
                    if !isPlaying && playerState != .idle && !isLoading {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.white.opacity(0.85))
                            .shadow(radius: 6)
                            .onTapGesture {
                                togglePlayPause()
                            }
                    }
                    
                    // 错误信息覆盖
                    if let err = errorMessage {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title)
                                .foregroundColor(.red)
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(16)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(10)
                        .padding(.horizontal, 20)
                    }
                    
                    // 空流列表引导
                    if apiService.streamList.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.system(size: 40))
                                .foregroundColor(.orange)
                            Text("当前节点暂无活跃在线流")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("请前往「配置」页检查节点域名，或点击下方按钮刷新")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            Button(action: {
                                apiService.fetchStreamList { streams in
                                    if !streams.isEmpty {
                                        currentStreamIndex = 0
                                        currentSourceIndex = 0
                                        playCurrentStreamAndSource()
                                    }
                                }
                            }) {
                                HStack {
                                    if apiService.isLoadingStreams {
                                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text("立即拉取节点流")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                            }
                        }
                        .padding()
                    }
                }
                .frame(height: geometry.size.height * 0.56) // 占屏幕高度 56%，完全独立
                .gesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            if value.translation.height < -40 {
                                // 向上滑 -> 下一个
                                switchNext()
                            } else if value.translation.height > 40 {
                                // 向下滑 -> 上一个
                                switchPrevious()
                            }
                        }
                )
                
                // MARK: - 2. 下半部分：独立的视频信息与主控面板 (仿微信/抖音交互分区)
                VStack(spacing: 10) {
                    // (1) 模式选择器与节点指示
                    HStack {
                        Picker("切换模式", selection: $switchMode) {
                            Text("切流 (\(currentStreamIndex + 1)/\(max(1, apiService.streamList.count)))").tag(FeedSwitchMode.stream)
                            Text("切内部地址 (\(currentSources.count > 0 ? "\(currentSourceIndex + 1)/\(currentSources.count)" : "0"))").tag(FeedSwitchMode.source)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        
                        Spacer()
                        
                        // 节点快捷切换菜单
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
                                HStack(spacing: 3) {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(.system(size: 9))
                                    Text(apiService.activeNodeItem?.remark.isEmpty == false ? apiService.activeNodeItem!.remark : apiService.activeNodeDomain)
                                        .font(.system(size: 10, weight: .bold))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(6)
                            }
                        }
                    }
                    .padding(.top, 8)
                    
                    // (2) 独立流信息卡片
                    if let stream = currentStream {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("📡 流 ID:")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.blue)
                                Text(stream.streamid)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer()
                                if !stream.resolutionText.isEmpty {
                                    Text(stream.resolutionText)
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundColor(.blue)
                                        .cornerRadius(4)
                                }
                            }
                            
                            HStack(spacing: 8) {
                                if !stream.fpsText.isEmpty {
                                    Text(stream.fpsText)
                                        .foregroundColor(.secondary)
                                }
                                if !stream.bitrateText.isEmpty {
                                    Text(stream.bitrateText)
                                        .foregroundColor(.green)
                                }
                                if !stream.locationText.isEmpty {
                                    Text(stream.locationText)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .font(.system(size: 10))
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.06))
                        .cornerRadius(8)
                    }
                    
                    // (3) 独立播放源卡片
                    if let source = currentSource {
                        HStack(spacing: 8) {
                            Text(source.type.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(source.type.lowercased() == "flv" ? Color.orange : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                            
                            if !source.codecText.isEmpty {
                                Text(source.codecText)
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12))
                                    .foregroundColor(.primary)
                                    .cornerRadius(4)
                            }
                            
                            if let v = source.vendor, !v.isEmpty {
                                Text(v.uppercased())
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text("地址 \(currentSourceIndex + 1)/\(currentSources.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.orange)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.06))
                        .cornerRadius(8)
                    }
                    
                    Spacer()
                    
                    // (4) 主控切换按钮条
                    HStack(spacing: 28) {
                        Button(action: {
                            switchPrevious()
                        }) {
                            VStack(spacing: 3) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 40))
                                Text(switchMode == .stream ? "上一路流" : "上个地址")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(canSwitchPrevious ? .blue : .gray.opacity(0.4))
                        }
                        .disabled(!canSwitchPrevious)
                        
                        // 播放/暂停
                        Button(action: {
                            togglePlayPause()
                        }) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 52))
                                .foregroundColor(.blue)
                        }
                        
                        Button(action: {
                            switchNext()
                        }) {
                            VStack(spacing: 3) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 40))
                                Text(switchMode == .stream ? "下一路流" : "下个地址")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(canSwitchNext ? .blue : .gray.opacity(0.4))
                        }
                        .disabled(!canSwitchNext)
                        
                        // 静音切换
                        Button(action: {
                            isMuted.toggle()
                            activePlayer?.setMute(isMuted)
                        }) {
                            VStack(spacing: 3) {
                                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 26))
                                    .frame(height: 40)
                                Text(isMuted ? "已静音" : "声音开")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(isMuted ? .red : .primary)
                        }
                    }
                    
                    // (5) 底部 QoS 实时指标条
                    if let qos = qosReport {
                        HStack(spacing: 10) {
                            Text("⚡️ 起播: \(String(format: "%.1f", qos.firstFrameDuration > 0 ? qos.firstFrameDuration : startLatencyMS)) ms")
                                .foregroundColor(.green)
                            Text("内核: \(qos.engineName)")
                                .foregroundColor(.primary)
                            Text("硬解: \(qos.isHardwareAccelerated ? "开" : "关")")
                                .foregroundColor(.secondary)
                        }
                        .font(.system(size: 9.5, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .background(Color(UIColor.systemBackground))
            }
        }
        .edgesIgnoringSafeArea(.top)
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
            return currentStreamIndex > 0
        } else {
            return currentSourceIndex > 0
        }
    }
    
    private var canSwitchNext: Bool {
        if switchMode == .stream {
            return currentStreamIndex < apiService.streamList.count - 1
        } else {
            return currentSourceIndex < currentSources.count - 1
        }
    }
    
    private func switchPrevious() {
        if switchMode == .stream {
            guard currentStreamIndex > 0 else { return }
            currentStreamIndex -= 1
            currentSourceIndex = 0
            playCurrentStreamAndSource()
        } else {
            guard currentSourceIndex > 0 else { return }
            currentSourceIndex -= 1
            playCurrentSourceItem()
        }
    }
    
    private func switchNext() {
        if switchMode == .stream {
            guard currentStreamIndex < apiService.streamList.count - 1 else { return }
            currentStreamIndex += 1
            currentSourceIndex = 0
            playCurrentStreamAndSource()
        } else {
            guard currentSourceIndex < currentSources.count - 1 else { return }
            currentSourceIndex += 1
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
