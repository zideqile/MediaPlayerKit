import SwiftUI
import MediaPlayerKit

public struct UniversalPlayerView: View {
    @State private var selectedPreset = MediaPreset.samples[0]
    @State private var customURLText = ""
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
    
    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // 视频渲染窗口
            ZStack(alignment: .topTrailing) {
                PlayerViewRepresentable(player: player)
                    .frame(minHeight: 280, maxHeight: 420)
                    .background(Color.black)
                
                // 实时 QoS 性能悬浮窗
                if showQoSOverlay, let qos = qosReport {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("⚡️ 实时 QoS 质量监控")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.yellow)
                        Text("内核: \(qos.engineName) | 硬解: \(qos.isHardwareAccelerated ? "开启" : "关闭")")
                        Text("分辨率: \(qos.videoWidth)x\(qos.videoHeight)")
                        Text("首帧耗时: \(String(format: "%.1f", qos.firstFrameDuration)) ms")
                        Text("卡顿次数: \(qos.stutterCount) 次 | 丢帧: \(qos.droppedFrames)")
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .padding(8)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(8)
                    .padding(10)
                }
            }
            
            // 进度条与播放控制栏
            VStack(spacing: 12) {
                // 时间进度条
                VStack(spacing: 4) {
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
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(timeString(duration))
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                // 按钮控制面板
                HStack(spacing: 20) {
                    Button(action: {
                        player.seek(to: max(0, currentPosition - 10))
                    }) {
                        Image(systemName: "gobackward.10")
                            .font(.title2)
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
                            .font(.system(size: 44))
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: {
                        player.seek(to: min(duration, currentPosition + 10))
                    }) {
                        Image(systemName: "goforward.10")
                            .font(.title2)
                    }
                    
                    Divider().frame(height: 24)
                    
                    // 倍速切换菜单
                    Menu {
                        ForEach([0.5, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                            Button("\(String(format: "%.2fx", rate))") {
                                playbackRate = Float(rate)
                                player.setPlaybackRate(Float(rate))
                            }
                        }
                    } label: {
                        Text("\(String(format: "%.1fx", playbackRate))")
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(6)
                    }
                    
                    // 静音与画中画
                    Button(action: {
                        isMuted.toggle()
                        player.setMute(isMuted)
                    }) {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    
                    Button(action: {
                        showQoSOverlay.toggle()
                    }) {
                        Image(systemName: showQoSOverlay ? "gauge.with.needle.fill" : "gauge.with.needle")
                            .foregroundColor(showQoSOverlay ? .yellow : .secondary)
                    }
                }
                .padding(.bottom, 6)
            }
            .background(Color(white: 0.12))
            
            // 预设流列表
            List {
                Section(header: Text("预设媒体流测试集")) {
                    ForEach(MediaPreset.samples) { preset in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(preset.title).font(.headline)
                                Text(preset.subtitle).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(preset.format)
                                .font(.caption2)
                                .padding(4)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            loadPreset(preset)
                        }
                    }
                }
            }
            #if os(iOS)
            .listStyle(InsetGroupedListStyle())
            #endif
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
            },
            onTimeUpdate: { cur, dur in
                self.currentPosition = cur
                self.duration = dur
                self.qosReport = self.player.currentQoSReport()
            }
        )
        player.delegate = coordinator
    }
    
    private func loadPreset(_ preset: MediaPreset) {
        selectedPreset = preset
        player.setMediaSource(url: preset.url)
        player.play()
        isPlaying = true
    }
    
    private func timeString(_ seconds: TimeInterval) -> String {
        let min = Int(seconds) / 60
        let sec = Int(seconds) % 60
        return String(format: "%02d:%02d", min, sec)
    }
}

// 代理中继器
final class PlayerCoordinator: NSObject, MediaPlayerDelegate {
    var onStateChange: ((PlayerState) -> Void)?
    var onTimeUpdate: ((TimeInterval, TimeInterval) -> Void)?

    init(onStateChange: @escaping (PlayerState) -> Void, onTimeUpdate: @escaping (TimeInterval, TimeInterval) -> Void) {
        self.onStateChange = onStateChange
        self.onTimeUpdate = onTimeUpdate
    }

    func player(_ player: MediaPlayerController, stateDidChange state: PlayerState) {
        DispatchQueue.main.async { self.onStateChange?(state) }
    }

    func player(_ player: MediaPlayerController, currentTime: TimeInterval, totalDuration: TimeInterval) {
        DispatchQueue.main.async { self.onTimeUpdate?(currentTime, totalDuration) }
    }

    func playerDidRenderFirstFrame(_ player: MediaPlayerController) {}
    func player(_ player: MediaPlayerController, didOccurError error: NSError) {}
}
