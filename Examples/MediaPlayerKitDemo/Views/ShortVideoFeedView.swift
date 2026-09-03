import SwiftUI
import MediaPlayerKit
#if canImport(UIKit)
import UIKit
#endif

/// 切换模式：切流（不同推流） vs 切内部源（同推流的不同协议/编码源）
public enum FeedSwitchMode: String, CaseIterable {
    case stream = "切流"
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
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            // MARK: - 1. 视频渲染背景层
            if let player = activePlayer {
                PlayerViewRepresentable(player: player)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        togglePlayPause()
                    }
            } else {
                Color.black.edgesIgnoringSafeArea(.all)
            }
            
            // MARK: - 2. 空流列表引导页
            if apiService.streamList.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    
                    Text("当前节点暂无活跃在线流")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("请在「全能播放器」配置节点并拉取流列表，或者点击下方按钮快速拉取")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
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
                            Text("立即拉取节点流列表")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            
            // MARK: - 3. 加载与错误提示
            if isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.4)
                    Text("正在调度拉流...")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(12)
                .background(Color.black.opacity(0.65))
                .cornerRadius(8)
            }
            
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
                .padding(12)
                .background(Color.black.opacity(0.75))
                .cornerRadius(8)
            }
            
            // MARK: - 4. 悬浮操控与信息层
            if !apiService.streamList.isEmpty {
                VStack(spacing: 0) {
                    // 顶部控制条：模式选择与流信息
                    VStack(alignment: .leading, spacing: 6) {
                        // 切换模式 Segmented Control
                        HStack {
                            Text("切换目标:")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                            
                            Picker("切换模式", selection: $switchMode) {
                                ForEach(FeedSwitchMode.allCases, id: \.self) { mode in
                                    Text(mode == .stream ? "切流 (\(currentStreamIndex + 1)/\(apiService.streamList.count))" : "切内部地址 (\(currentSources.count > 0 ? "\(currentSourceIndex + 1)/\(currentSources.count)" : "0"))").tag(mode)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(8)
                            
                            Spacer()
                            
                            // 静音按钮
                            Button(action: {
                                isMuted.toggle()
                                activePlayer?.setMute(isMuted)
                            }) {
                                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(isMuted ? .red : .white)
                                    .padding(6)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                        }
                        
                        // 当前流详情卡片
                        if let stream = currentStream {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("📡 流 ID:")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.yellow)
                                    Text(stream.streamid)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    if !stream.resolutionText.isEmpty {
                                        Text(stream.resolutionText)
                                            .font(.system(size: 9))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.white.opacity(0.2))
                                            .foregroundColor(.white)
                                            .cornerRadius(3)
                                    }
                                }
                                
                                HStack(spacing: 8) {
                                    if !stream.fpsText.isEmpty {
                                        Text(stream.fpsText)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                    if !stream.bitrateText.isEmpty {
                                        Text(stream.bitrateText)
                                            .foregroundColor(.green)
                                    }
                                    if !stream.locationText.isEmpty {
                                        Text(stream.locationText)
                                            .foregroundColor(.white.opacity(0.8))
                                            .lineLimit(1)
                                    }
                                }
                                .font(.system(size: 9))
                            }
                            .padding(6)
                            .background(Color.black.opacity(0.55))
                            .cornerRadius(6)
                        }
                        
                        // 当前播放源卡片
                        if let source = currentSource {
                            HStack(spacing: 6) {
                                Text(source.type.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(source.type.lowercased() == "flv" ? Color.orange : Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(3)
                                
                                if !source.codecText.isEmpty {
                                    Text(source.codecText)
                                        .font(.system(size: 9, weight: .medium))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.2))
                                        .foregroundColor(.white)
                                        .cornerRadius(3)
                                }
                                
                                if let v = source.vendor, !v.isEmpty {
                                    Text(v.uppercased())
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                
                                Spacer()
                                
                                Text("源 \(currentSourceIndex + 1)/\(currentSources.count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                            .padding(6)
                            .background(Color.black.opacity(0.55))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    
                    Spacer()
                    
                    // 底部控制按钮与 QoS 指示器
                    VStack(spacing: 10) {
                        // 实时 QoS 悬浮小标
                        if let qos = qosReport {
                            HStack(spacing: 12) {
                                Text("⚡️ 起播: \(String(format: "%.1f", qos.firstFrameDuration > 0 ? qos.firstFrameDuration : startLatencyMS)) ms")
                                    .foregroundColor(.green)
                                Text("内核: \(qos.engineName)")
                                    .foregroundColor(.yellow)
                                Text("硬解: \(qos.isHardwareAccelerated ? "开启" : "关闭")")
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .font(.system(size: 9.5, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.65))
                            .cornerRadius(12)
                        }
                        
                        // 上一个 / 下一个 主控按钮条
                        HStack(spacing: 36) {
                            Button(action: {
                                switchPrevious()
                            }) {
                                VStack(spacing: 3) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 42))
                                    Text(switchMode == .stream ? "上一路流" : "上一个源")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundColor(canSwitchPrevious ? .white : .gray.opacity(0.5))
                            }
                            .disabled(!canSwitchPrevious)
                            
                            // 播放/暂停
                            Button(action: {
                                togglePlayPause()
                            }) {
                                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.blue)
                            }
                            
                            Button(action: {
                                switchNext()
                            }) {
                                VStack(spacing: 3) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 42))
                                    Text(switchMode == .stream ? "下一路流" : "下一个源")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundColor(canSwitchNext ? .white : .gray.opacity(0.5))
                            }
                            .disabled(!canSwitchNext)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.height < -50 {
                        // 向上滑动 -> 下一个
                        switchNext()
                    } else if value.translation.height > 50 {
                        // 向下滑动 -> 上一个
                        switchPrevious()
                    }
                }
        )
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
