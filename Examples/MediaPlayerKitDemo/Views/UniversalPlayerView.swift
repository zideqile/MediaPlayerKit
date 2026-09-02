import SwiftUI
import MediaPlayerKit
#if canImport(UIKit)
import UIKit
#endif

public struct UniversalPlayerView: View {
    @StateObject private var apiService = StreamAPIService.shared
    
    @State private var selectedPreset: MediaPreset = MediaPreset.samples[0]
    @State private var customURLText: String = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
    @State private var player = MediaPlayerController()
    
    @State private var isPlaying = false
    @State private var currentPosition: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var bufferedDuration: TimeInterval = 0
    @State private var playerState: PlayerState = .idle
    @State private var playbackRate: Float = 1.0
    @State private var isMuted = false
    @State private var showQoSOverlay = true
    @State private var qosReport: PlayerQoSReport?
    @State private var errorMessage: String?
    
    @State private var showConfigSection = true
    @State private var currentPlayingTitle: String = "待播放"
    
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // MARK: - 1. 顶部视频渲染窗口
                ZStack(alignment: .topTrailing) {
                    PlayerViewRepresentable(player: player)
                        .frame(height: 220)
                        .background(Color.black)
                    
                    // 状态加载指示器
                    if playerState == .preparing || playerState == .buffering {
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
                    
                    // 实时 QoS 性能悬浮窗
                    if showQoSOverlay, let qos = qosReport {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("⚡️ QoS 监控")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.yellow)
                                Spacer()
                                Text(currentPlayingTitle)
                                    .font(.system(size: 8))
                                    .foregroundColor(.green)
                                    .lineLimit(1)
                            }
                            Text("内核: \(qos.engineName) | 硬解: \(qos.isHardwareAccelerated ? "开" : "关")")
                            Text("分辨率: \(qos.videoWidth)x\(qos.videoHeight) | 状态: \(playerState.description)")
                            Text("首帧耗时: \(String(format: "%.1f", qos.firstFrameDuration)) ms")
                        }
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(5)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(6)
                        .padding(6)
                    }
                }
                
                // MARK: - 2. 进度条与播放控制栏
                VStack(spacing: 6) {
                    // 时间进度条
                    VStack(spacing: 2) {
                        Slider(value: $currentPosition, in: 0...max(1, duration)) { editing in
                            if !editing {
                                player.seek(to: currentPosition)
                            }
                        }
                        .accentColor(.blue)
                        
                        HStack {
                            Text(timeString(currentPosition))
                            Spacer()
                            Text("状态: \(playerState.description)")
                                .foregroundColor(playerState == .playing ? .green : .secondary)
                            Spacer()
                            Text(timeString(duration))
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    
                    // 控制按钮条
                    HStack(spacing: 20) {
                        Button(action: {
                            player.seek(to: max(0, currentPosition - 10))
                        }) {
                            Image(systemName: "gobackward.10")
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        
                        Button(action: {
                            if isPlaying {
                                player.pause()
                                isPlaying = false
                            } else {
                                player.play()
                                isPlaying = true
                            }
                        }) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.blue)
                        }
                        
                        Button(action: {
                            player.seek(to: min(duration, currentPosition + 10))
                        }) {
                            Image(systemName: "goforward.10")
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        
                        Divider().frame(height: 18)
                        
                        // 倍速切换菜单
                        Menu {
                            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                                Button("\(String(format: "%.2fx", rate))") {
                                    playbackRate = Float(rate)
                                    player.setPlaybackRate(Float(rate))
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
                        
                        // 静音切换
                        Button(action: {
                            isMuted.toggle()
                            player.setMute(isMuted)
                        }) {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .foregroundColor(isMuted ? .red : .primary)
                        }
                        
                        // QoS 悬浮窗开关
                        Button(action: {
                            showQoSOverlay.toggle()
                        }) {
                            Image(systemName: showQoSOverlay ? "gauge.with.needle.fill" : "gauge.with.needle")
                                .foregroundColor(showQoSOverlay ? .yellow : .secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08))
                
                // MARK: - 3. 域名、节点域名与 Sign 配置区
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(.blue)
                        Text("流调度与节点配置")
                            .font(.system(size: 13, weight: .bold))
                        Spacer()
                        Button(action: {
                            withAnimation { showConfigSection.toggle() }
                        }) {
                            Text(showConfigSection ? "收起" : "展开配置")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    if showConfigSection {
                        VStack(spacing: 8) {
                            HStack {
                                Text("接口域名:")
                                    .font(.caption)
                                    .frame(width: 68, alignment: .leading)
                                TextField("输入接口域名", text: $apiService.apiDomain)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.caption)
                            }
                            
                            HStack {
                                Text("节点域名:")
                                    .font(.caption)
                                    .frame(width: 68, alignment: .leading)
                                TextField("输入节点域名 (含端口)", text: $apiService.nodeDomain)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.caption)
                            }
                            
                            HStack {
                                Text("Sign 参数:")
                                    .font(.caption)
                                    .frame(width: 68, alignment: .leading)
                                TextField("输入 Sign 参数", text: $apiService.sign)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.caption)
                            }
                            
                            Button(action: {
                                apiService.fetchStreamList()
                            }) {
                                HStack {
                                    if apiService.isLoadingStreams {
                                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text("获取流列表")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(apiService.hasCompleteConfig ? Color.blue : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                            }
                            .disabled(!apiService.hasCompleteConfig)
                        }
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                
                // MARK: - 4. 节点流列表区
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.green)
                        Text("节点流列表")
                            .font(.system(size: 13, weight: .bold))
                        
                        if !apiService.streamList.isEmpty {
                            Text("\(apiService.streamList.count) 条")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(8)
                        }
                        Spacer()
                        
                        if apiService.hasCompleteConfig {
                            Button(action: {
                                apiService.fetchStreamList()
                            }) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
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
                    } else if let err = apiService.streamListError {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.orange)
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                    } else if apiService.streamList.isEmpty {
                        Text("暂无流数据，请填写上方配置后获取")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                    } else {
                        // 流列表横向展示
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(apiService.streamList) { stream in
                                    Button(action: {
                                        apiService.fetchPlayerSources(for: stream.streamid)
                                    }) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(stream.streamid)
                                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.primary)
                                                    .lineLimit(1)
                                                Spacer()
                                                if apiService.selectedStreamId == stream.streamid {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(.blue)
                                                        .font(.caption2)
                                                }
                                            }
                                            
                                            HStack(spacing: 6) {
                                                if !stream.resolutionText.isEmpty {
                                                    Text(stream.resolutionText)
                                                }
                                                if !stream.fpsText.isEmpty {
                                                    Text(stream.fpsText)
                                                }
                                            }
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                            
                                            HStack(spacing: 6) {
                                                if !stream.bitrateText.isEmpty {
                                                    Text(stream.bitrateText)
                                                        .foregroundColor(.blue)
                                                }
                                                if !stream.locationText.isEmpty {
                                                    Text(stream.locationText)
                                                        .foregroundColor(.secondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                            .font(.system(size: 9))
                                        }
                                        .padding(8)
                                        .frame(width: 210)
                                        .background(apiService.selectedStreamId == stream.streamid ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(apiService.selectedStreamId == stream.streamid ? Color.blue : Color.clear, lineWidth: 1.5)
                                        )
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, 10)
                        }
                    }
                }
                
                // MARK: - 5. 选定流的播放地址源列表（选择即播）
                if let streamId = apiService.selectedStreamId {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "play.rectangle.on.rectangle.fill")
                                .foregroundColor(.orange)
                            Text("播放地址列表 (流: \(streamId))")
                                .font(.system(size: 13, weight: .bold))
                            Spacer()
                            if apiService.isLoadingSources {
                                ProgressView().scaleEffect(0.8)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                        
                        if let err = apiService.sourcesError {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal, 10)
                        } else if let container = apiService.playerSources {
                            let allSources = container.allSources
                            if allSources.isEmpty {
                                Text("未查询到可用播放地址")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(allSources) { source in
                                        Button(action: {
                                            playSource(source, streamId: streamId)
                                        }) {
                                            HStack(alignment: .center, spacing: 8) {
                                                // 协议 Badge
                                                Text(source.type.uppercased())
                                                    .font(.system(size: 10, weight: .bold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 3)
                                                    .background(source.type.lowercased() == "flv" ? Color.orange : Color.blue)
                                                    .foregroundColor(.white)
                                                    .cornerRadius(4)
                                                
                                                // 编码 Badge
                                                if !source.codecText.isEmpty {
                                                    Text(source.codecText)
                                                        .font(.system(size: 9, weight: .medium))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 2)
                                                        .background(Color.secondary.opacity(0.15))
                                                        .foregroundColor(.primary)
                                                        .cornerRadius(3)
                                                }
                                                
                                                if let v = source.vendor, !v.isEmpty {
                                                    Text(v.uppercased())
                                                        .font(.system(size: 9))
                                                        .foregroundColor(.secondary)
                                                }
                                                
                                                Spacer()
                                                
                                                // 播放按钮
                                                HStack(spacing: 3) {
                                                    Image(systemName: "play.fill")
                                                        .font(.system(size: 9))
                                                    Text("播放")
                                                        .font(.system(size: 11, weight: .bold))
                                                }
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.green)
                                                .foregroundColor(.white)
                                                .cornerRadius(4)
                                            }
                                            .padding(8)
                                            .background(Color.secondary.opacity(0.06))
                                            .cornerRadius(6)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 10)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                
                // MARK: - 6. 手动自定义链接输入区域
                VStack(alignment: .leading, spacing: 8) {
                    Text("🔗 手动指定视频链接")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    
                    HStack {
                        TextField("输入或粘贴视频链接 (flv/rtmp/m3u8/mp4)...", text: $customURLText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.system(size: 12))
                        
                        if !customURLText.isEmpty {
                            Button(action: { customURLText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        #if canImport(UIKit)
                        Button(action: {
                            if let clip = UIPasteboard.general.string, !clip.isEmpty {
                                customURLText = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }) {
                            Text("粘贴")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(5)
                        }
                        #endif
                    }
                    
                    Button(action: {
                        playCustomURL()
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("立即播放自定义链接")
                                .fontWeight(.bold)
                        }
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                
                // MARK: - 7. 经典预设流集
                VStack(alignment: .leading, spacing: 8) {
                    Text("📺 经典测试流集（点击即播）")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                    
                    VStack(spacing: 6) {
                        ForEach(MediaPreset.samples) { preset in
                            Button(action: {
                                loadPreset(preset)
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.primary)
                                            .multilineTextAlignment(.leading)
                                        Text(preset.subtitle)
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(preset.format)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(selectedPreset.id == preset.id ? Color.blue : Color.secondary.opacity(0.15))
                                        .foregroundColor(selectedPreset.id == preset.id ? .white : .primary)
                                        .cornerRadius(4)
                                }
                                .padding(8)
                                .background(Color.secondary.opacity(0.06))
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            setupPlayer()
            if apiService.hasCompleteConfig {
                apiService.fetchStreamList()
            }
            loadPreset(selectedPreset)
        }
        .onDisappear {
            player.stop()
        }
    }
    
    private func setupPlayer() {
        let coordinator = PlayerCoordinator(
            onStateChange: { state in
                self.playerState = state
                self.isPlaying = (state == .playing)
                if state == .playing {
                    self.errorMessage = nil
                }
            },
            onTimeUpdate: { cur, dur in
                self.currentPosition = cur
                self.duration = dur
                self.qosReport = self.player.currentQoSReport()
            },
            onError: { err in
                self.errorMessage = "播放出错: \(err.localizedDescription)"
                self.isPlaying = false
            }
        )
        player.delegate = coordinator
    }
    
    private func playSource(_ source: PlayerSourceItem, streamId: String) {
        customURLText = source.src
        currentPlayingTitle = "[\(source.type.uppercased())] \(streamId)"
        guard let url = URL(string: source.src) else {
            self.errorMessage = "无效的播放地址 URL"
            return
        }
        self.errorMessage = nil
        player.setMediaSource(url: url)
        player.play()
        isPlaying = true
    }
    
    private func playCustomURL() {
        let trimmed = customURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else {
            self.errorMessage = "无效的 URL 地址，请检查格式"
            return
        }
        self.errorMessage = nil
        currentPlayingTitle = "自定义链接"
        player.setMediaSource(url: url)
        player.play()
        isPlaying = true
    }
    
    private func loadPreset(_ preset: MediaPreset) {
        selectedPreset = preset
        customURLText = preset.url.absoluteString
        self.errorMessage = nil
        currentPlayingTitle = preset.title
        player.setMediaSource(url: preset.url)
        player.play()
        isPlaying = true
    }
    
    private func timeString(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "00:00" }
        let min = Int(seconds) / 60
        let sec = Int(seconds) % 60
        return String(format: "%02d:%02d", min, sec)
    }
}

// 代理中继器
final class PlayerCoordinator: NSObject, MediaPlayerDelegate {
    var onStateChange: ((PlayerState) -> Void)?
    var onTimeUpdate: ((TimeInterval, TimeInterval) -> Void)?
    var onError: ((NSError) -> Void)?

    init(
        onStateChange: @escaping (PlayerState) -> Void,
        onTimeUpdate: @escaping (TimeInterval, TimeInterval) -> Void,
        onError: @escaping (NSError) -> Void
    ) {
        self.onStateChange = onStateChange
        self.onTimeUpdate = onTimeUpdate
        self.onError = onError
    }

    func player(_ player: MediaPlayerController, stateDidChange state: PlayerState) {
        DispatchQueue.main.async { self.onStateChange?(state) }
    }

    func player(_ player: MediaPlayerController, currentTime: TimeInterval, totalDuration: TimeInterval) {
        DispatchQueue.main.async { self.onTimeUpdate?(currentTime, totalDuration) }
    }

    func playerDidRenderFirstFrame(_ player: MediaPlayerController) {}
    
    func player(_ player: MediaPlayerController, didOccurError error: NSError) {
        DispatchQueue.main.async { self.onError?(error) }
    }
}
