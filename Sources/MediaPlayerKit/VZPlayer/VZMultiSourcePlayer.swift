import Foundation
import CoreGraphics

public protocol VZMultiSourcePlayerDelegate: AnyObject {
    func multiSourcePlayer(_ player: VZMultiSourcePlayer, stateDidChange state: PlayerState)
    func multiSourcePlayer(_ player: VZMultiSourcePlayer, didRenderFirstFrame: Void)
    func multiSourcePlayer(_ player: VZMultiSourcePlayer, currentTime: TimeInterval, totalDuration: TimeInterval)
    func multiSourcePlayer(_ player: VZMultiSourcePlayer, didOccurError error: NSError)
    func multiSourcePlayerDidPlayToEnd(_ player: VZMultiSourcePlayer)
    func multiSourcePlayer(_ player: VZMultiSourcePlayer, didSwitchToSource source: VZPlayerSource)
    func multiSourcePlayer(_ player: VZMultiSourcePlayer, didWarnMessage msg: String)
}

/// 多播放源管理器与两层容错调度器 (对标 vzplayer 的 MultiSourcePlayer & PlayerSelector)
public final class VZMultiSourcePlayer: NSObject, MediaPlayerDelegate {
    public weak var delegate: VZMultiSourcePlayerDelegate?
    
    public private(set) var sources: [VZPlayerSource] = []
    public private(set) var currentSourceIndex: Int = 0
    
    // 内核尝试顺序：0: AVPlayer (硬解), 1: KSMEPlayer (软解)
    private var engineOrder: [PlayerEngineType] = [.avPlayer, .mePlayer]
    private var currentEngineIndex: Int = 0
    
    private var controller: MediaPlayerController?
    private let playerView: MediaPlayerView
    private var playerConfig: VZPlayerConfig
    
    // 保存用户状态
    private var savedVolume: Float = 1.0
    private var savedMuted: Bool = false
    private var savedLoop: Bool = false
    private var savedSpeed: Float = 1.0
    private var isDestroyed: Bool = false
    
    public init(playerView: MediaPlayerView, config: VZPlayerConfig = VZPlayerConfig()) {
        self.playerView = playerView
        self.playerConfig = config
        self.savedVolume = config.volume
        self.savedMuted = config.muted
        self.savedLoop = config.loop
        self.savedSpeed = config.speed
        super.init()
    }
    
    public var currentSource: VZPlayerSource? {
        guard currentSourceIndex >= 0 && currentSourceIndex < sources.count else {
            return nil
        }
        return sources[currentSourceIndex]
    }
    
    public func setSources(_ sources: [VZPlayerSource]) {
        self.sources = sources
        self.currentSourceIndex = 0
        self.currentEngineIndex = 0
    }
    
    public func setConfig(_ config: VZPlayerConfig) {
        self.playerConfig = config
    }
    
    // MARK: - 播放控制
    
    public func play() {
        guard !sources.isEmpty else {
            delegate?.multiSourcePlayer(self, didOccurError: NSError(domain: "VZMultiSourcePlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "sources is empty"]))
            return
        }
        if controller == nil {
            startPlaybackWithCurrentSourceAndEngine()
        } else {
            controller?.play()
        }
    }
    
    public func pause() {
        controller?.pause()
    }
    
    public func resume() {
        controller?.play()
    }
    
    public func destroy() {
        isDestroyed = true
        controller?.stop()
        controller?.delegate = nil
        controller = nil
    }
    
    public func seek(to time: TimeInterval) {
        controller?.seek(to: time)
    }
    
    public func setVolume(_ volume: Float) {
        savedVolume = volume
        controller?.setVolume(volume)
    }
    
    public func getVolume() -> Float {
        return savedVolume
    }
    
    public func setMuted(_ isMuted: Bool) {
        savedMuted = isMuted
        controller?.setMute(isMuted)
    }
    
    public func isMuted() -> Bool {
        return savedMuted
    }
    
    public func setLoop(_ loop: Bool) {
        savedLoop = loop
        // 可设置底层的循环控制
    }
    
    public func isLoop() -> Bool {
        return savedLoop
    }
    
    public func setSpeed(_ speed: Float) {
        savedSpeed = speed
        controller?.setPlaybackRate(speed)
    }
    
    public func getSpeed() -> Float {
        return savedSpeed
    }
    
    public var currentTime: TimeInterval {
        return controller?.currentPosition ?? 0
    }
    
    public var duration: TimeInterval {
        return controller?.duration ?? 0
    }
    
    public var bufferedDuration: TimeInterval {
        return controller?.bufferedDuration ?? 0
    }
    
    public var isPaused: Bool {
        guard let ctrl = controller else { return true }
        return !ctrl.isPlaying
    }
    
    public var naturalSize: CGSize {
        return controller?.naturalSize ?? .zero
    }
    
    // MARK: - 内部容错调度
    
    private func startPlaybackWithCurrentSourceAndEngine() {
        guard !isDestroyed, let source = currentSource, let url = URL(string: source.url) else {
            delegate?.multiSourcePlayer(self, didOccurError: NSError(domain: "VZMultiSourcePlayer", code: -1001, userInfo: [NSLocalizedDescriptionKey: "Invalid source URL"]))
            return
        }
        
        let engineType = engineOrder[currentEngineIndex]
        
        // 1. 释放旧的控制器
        controller?.stop()
        controller?.delegate = nil
        playerView.detachRenderView()
        
        // 2. 创建新控制器并配置
        let config = PlayerConfig()
        config.preferredEngine = engineType
        config.enableHardwareDecoding = (engineType == .avPlayer)
        
        let ctrl = MediaPlayerController(config: config)
        ctrl.delegate = self
        self.controller = ctrl
        
        // 3. 附加渲染视图
        playerView.attachRenderView(ctrl.playerView)
        
        // 4. 应用缓存的状态
        ctrl.setVolume(savedVolume)
        ctrl.setMute(savedMuted)
        ctrl.setPlaybackRate(savedSpeed)
        
        // 5. 开始加载与起播
        delegate?.multiSourcePlayer(self, didSwitchToSource: source)
        ctrl.setMediaSource(url: url)
        ctrl.play()
    }
    
    /// 触发容错重试流程 (Layer 1 内核重试 -> Layer 2 地址切换)
    private func handleRetry(error: NSError) {
        guard !isDestroyed else { return }
        
        let errorMsg = error.localizedDescription
        let isNotFound = error.code == 404 || errorMsg.contains("404") || errorMsg.contains("not found")
        
        if isNotFound {
            // 404 流不存在，跳过 Layer 1 内核重试，直接尝试 Layer 2 下一个地址
            delegate?.multiSourcePlayer(self, didWarnMessage: "Stream not found (404), skip engine retry")
            tryNextSource(lastError: error)
            return
        }
        
        // Layer 1: 尝试下一个内核
        if currentEngineIndex + 1 < engineOrder.count {
            currentEngineIndex += 1
            delegate?.multiSourcePlayer(self, didWarnMessage: "Retry with fallback engine: \(engineOrder[currentEngineIndex])")
            startPlaybackWithCurrentSourceAndEngine()
        } else {
            // Layer 1 内核全部耗尽，尝试 Layer 2 地址切换
            tryNextSource(lastError: error)
        }
    }
    
    private func tryNextSource(lastError: NSError) {
        if currentSourceIndex + 1 < sources.count {
            currentSourceIndex += 1
            currentEngineIndex = 0
            delegate?.multiSourcePlayer(self, didWarnMessage: "Switch to nextSource [\(currentSourceIndex + 1)/\(sources.count)]")
            startPlaybackWithCurrentSourceAndEngine()
        } else {
            // 所有地址和内核全部耗尽，最终上报错误
            delegate?.multiSourcePlayer(self, didOccurError: lastError)
        }
    }
    
    public func switchToNextSource() -> Bool {
        if currentSourceIndex + 1 < sources.count {
            currentSourceIndex += 1
            currentEngineIndex = 0
            startPlaybackWithCurrentSourceAndEngine()
            return true
        }
        return false
    }
    
    // MARK: - MediaPlayerDelegate 代理桥接
    
    public func player(_ player: MediaPlayerController, stateDidChange state: PlayerState) {
        delegate?.multiSourcePlayer(self, stateDidChange: state)
    }
    
    public func playerDidRenderFirstFrame(_ player: MediaPlayerController) {
        delegate?.multiSourcePlayer(self, didRenderFirstFrame: ())
    }
    
    public func player(_ player: MediaPlayerController, currentTime: TimeInterval, totalDuration: TimeInterval) {
        delegate?.multiSourcePlayer(self, currentTime: currentTime, totalDuration: totalDuration)
    }
    
    public func player(_ player: MediaPlayerController, didOccurError error: NSError) {
        handleRetry(error: error)
    }
    
    public func playerDidPlayToEndTime(_ player: MediaPlayerController) {
        delegate?.multiSourcePlayerDidPlayToEnd(self)
    }
}
