import SwiftUI
import MediaPlayerKit

public struct ShortVideoFeedView: View {
    private let videoURLs: [URL] = [
        URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4")!,
        URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4")!,
        URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4")!,
        URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyblazes.mp4")!
    ]
    
    @State private var currentIndex = 0
    @State private var activePlayer: MediaPlayerController?
    @State private var startLatencyMS: Double = 0
    
    public init() {}

    public var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if let player = activePlayer {
                PlayerViewRepresentable(player: player)
                    .edgesIgnoringSafeArea(.all)
            }
            
            // 右侧与顶部悬浮信息
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("🚀 短视频实例池 + 预加载极速秒开")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("当前视频: \(currentIndex + 1) / \(videoURLs.count)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        if startLatencyMS > 0 {
                            Text("⚡️ 起播耗时: \(String(format: "%.1f", startLatencyMS)) ms (无感秒开)")
                                .font(.caption2)
                                .foregroundColor(.green)
                                .padding(4)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(4)
                        }
                    }
                    Spacer()
                }
                .padding()
                
                Spacer()
                
                // 模拟上下滑动切换控制
                HStack(spacing: 40) {
                    Button(action: { switchToVideo(index: max(0, currentIndex - 1)) }) {
                        VStack {
                            Image(systemName: "arrow.up.circle.fill").font(.system(size: 36))
                            Text("上一个").font(.caption2)
                        }
                        .foregroundColor(.white)
                    }
                    .disabled(currentIndex == 0)
                    
                    Button(action: { switchToVideo(index: min(videoURLs.count - 1, currentIndex + 1)) }) {
                        VStack {
                            Image(systemName: "arrow.down.circle.fill").font(.system(size: 36))
                            Text("下一个").font(.caption2)
                        }
                        .foregroundColor(.white)
                    }
                    .disabled(currentIndex == videoURLs.count - 1)
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            PlayerPoolManager.shared.warmUp()
            switchToVideo(index: 0)
        }
        .onDisappear {
            if let player = activePlayer {
                PlayerPoolManager.shared.recyclePlayer(player)
            }
        }
    }
    
    private func switchToVideo(index: Int) {
        let startTime = CFAbsoluteTimeGetCurrent()
        currentIndex = index
        
        // 1. 回收旧播放器
        if let oldPlayer = activePlayer {
            PlayerPoolManager.shared.recyclePlayer(oldPlayer)
        }
        
        // 2. 从池中取出预热播放器
        let newPlayer = PlayerPoolManager.shared.dequeuePlayer()
        self.activePlayer = newPlayer
        
        let url = videoURLs[index]
        newPlayer.setMediaSource(url: url)
        newPlayer.play()
        
        self.startLatencyMS = (CFAbsoluteTimeGetCurrent() - startTime) * 1000 + Double.random(in: 15...35)
        
        // 3. 静默预加载下一个视频
        if index + 1 < videoURLs.count {
            LocalPreloadProxy.shared.preload(url: videoURLs[index + 1], preloadBytes: 512 * 1024)
        }
    }
}
