import SwiftUI
import MediaPlayerKit
#if canImport(UIKit)
import UIKit
#endif

public struct UniversalPlayerView: View {
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
    @State private var selectedEngineIndex = 0
    @State private var errorMessage: String?
    
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 1. 视频渲染窗口
                ZStack(alignment: .topTrailing) {
                    PlayerViewRepresentable(player: player)
                        .frame(height: 230)
                        .background(Color.black)
                    
                    // 状态加载指示器
                    if playerState == .preparing || playerState == .buffering {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    // 错误提示蒙层
                    if let err = errorMessage {
                        VStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title)
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
                            Text("⚡️ QoS 实时监控")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.yellow)
                            Text("内核: \(qos.engineName) | 硬解: \(qos.isHardwareAccelerated ? "开启" : "关闭")")
                            Text("分辨率: \(qos.videoWidth)x\(qos.videoHeight)")
                            Text("状态: \(playerState.description)")
                            Text("首帧耗时: \(String(format: "%.1f", qos.firstFrameDuration)) ms")
                        }
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(6)
                        .padding(8)
                    }
                }
                
                // 2. 进度条与播放控制栏
                VStack(spacing: 8) {
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
                    HStack(spacing: 24) {
                        Button(action: {
                            player.seek(to: max(0, currentPosition - 10))
                        }) {
                            Image(systemName: "gobackward.10")
                                .font(.title3)
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
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                        }
                        
                        Button(action: {
                            player.seek(to: min(duration, currentPosition + 10))
                        }) {
                            Image(systemName: "goforward.10")
                                .font(.title3)
                                .foregroundColor(.primary)
                        }
                        
                        Divider().frame(height: 20)
                        
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
                                .font(.system(size: 12, weight: .bold))
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
                    .padding(.bottom, 6)
                }
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08))
                
                // 3. 自定义链接输入区域
                VStack(alignment: .leading, spacing: 10) {
                    Text("🔗 自定义视频链接输入")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                    
                    HStack {
                        TextField("输入或粘贴视频链接 (http/https/m3u8/mp4)...", text: $customURLText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.system(size: 13))
                        
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
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(6)
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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 12)
                
                // 4. 预设测试流列表
                VStack(alignment: .leading, spacing: 10) {
                    Text("📺 预设测试流集（点击即播）")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    VStack(spacing: 8) {
                        ForEach(MediaPreset.samples) { preset in
                            Button(action: {
                                loadPreset(preset)
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(preset.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.primary)
                                            .multilineTextAlignment(.leading)
                                        Text(preset.subtitle)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(preset.format)
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(selectedPreset.id == preset.id ? Color.blue : Color.secondary.opacity(0.15))
                                        .foregroundColor(selectedPreset.id == preset.id ? .white : .primary)
                                        .cornerRadius(4)
                                }
                                .padding(10)
                                .background(Color.secondary.opacity(0.06))
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            setupPlayer()
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
    
    private func playCustomURL() {
        let trimmed = customURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else {
            self.errorMessage = "无效的 URL 地址，请检查格式"
            return
        }
        self.errorMessage = nil
        player.setMediaSource(url: url)
        player.play()
        isPlaying = true
    }
    
    private func loadPreset(_ preset: MediaPreset) {
        selectedPreset = preset
        customURLText = preset.url.absoluteString
        self.errorMessage = nil
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
