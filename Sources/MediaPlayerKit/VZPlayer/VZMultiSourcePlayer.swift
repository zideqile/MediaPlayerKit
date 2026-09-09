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

/// 多播放源管理器与两层容错调度器 (实现 IPlayer 协议，对标 vzplayer 的 MultiSourcePlayer & PlayerSelector)
public final class VZMultiSourcePlayer: NSObject, IPlayer, MediaPlayerDelegate {
    public weak var delegate: VZMultiSourcePlayerDelegate?
    private var eventListeners: [VZPlayerEventListener] = []
    
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
    private var needsReloadSource: Bool = false
    
    public init(playerView: MediaPlayerView, config: VZPlayerConfig = VZPlayerConfig()) {
        self.playerView = playerView
        self.playerConfig = config
        self.savedVolume = config.volume
        self.savedMuted = config.muted
        self.savedLoop = config.loop
        self.savedSpeed = config.speed
        super.init()
    }
    
    // MARK: - IPlayer: 事件监听器
    
    public func AddEventListener(_ listener: VZPlayerEventListener?) {
        guard let l = listener else { return }
        if !eventListeners.contains(where: { $0 === l }) {
            eventListeners.append(l)
        }
    }
    
    public func RemoveEventListener(_ listener: VZPlayerEventListener?) {
        guard let l = listener else { return }
        eventListeners.removeAll(where: { $0 === l })
    }
    
    // MARK: - IPlayer: 基础播放控制
    
    public func Play(_ sources: [VZPlayerSource]) -> Bool {
        self.setSources(sources)
        self.Play()
        return true
    }
    
    public func Play() {
        guard !sources.isEmpty else {
            let err = NSError(domain: "VZMultiSourcePlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "sources is empty"])
            delegate?.multiSourcePlayer(self, didOccurError: err)
            for l in eventListeners { l.onError(code: -1, errMsg: "sources is empty") }
            return
        }
        if controller == nil || needsReloadSource {
            needsReloadSource = false
            startPlaybackWithCurrentSourceAndEngine()
        } else {
            if controller?.state == .completed {
                controller?.seek(to: 0)
            }
            controller?.play()
        }
    }
    
    public func Pause() {
        controller?.pause()
    }
    
    public func Resume() {
        controller?.play()
    }
    
    public func Destroy() {
        isDestroyed = true
        controller?.stop()
        controller?.delegate = nil
        controller = nil
        eventListeners.removeAll()
    }
    
    // MARK: - IPlayer: 进度与状态
    
    public func Seek(_ seconds: Int64) {
        controller?.seek(to: TimeInterval(seconds))
    }
    
    public func GetCurrentTime() -> Int64 {
        return Int64(controller?.currentPosition ?? 0)
    }
    
    public func GetDuration() -> Int64 {
        return Int64(controller?.duration ?? 0)
    }
    
    public func IsPaused() -> Bool {
        guard let ctrl = controller else { return true }
        return !ctrl.isPlaying
    }
    
    // MARK: - IPlayer: 音量与静音
    
    public func GetVolume() -> Float {
        return savedVolume
    }
    
    public func SetVolume(_ volume: Float) {
        savedVolume = volume
        controller?.setVolume(volume)
    }
    
    public func IsMuted() -> Bool {
        return savedMuted
    }
    
    public func SetMuted(_ isMuted: Bool) {
        savedMuted = isMuted
        controller?.setMute(isMuted)
    }
    
    // MARK: - IPlayer: 画面与循环
    
    public func GetWidth() -> Int {
        return Int(controller?.naturalSize.width ?? 0)
    }
    
    public func GetHeight() -> Int {
        return Int(controller?.naturalSize.height ?? 0)
    }
    
    public func IsLoop() -> Bool {
        return savedLoop
    }
    
    public func SetLoop(_ loop: Bool) {
        savedLoop = loop
        controller?.setLoop(loop)
    }
    
    // MARK: - IPlayer: 倍速与缓冲
    
    public func GetSpeed() -> Float {
        return savedSpeed
    }
    
    public func SetSpeed(_ speed: Float) {
        savedSpeed = speed
        controller?.setPlaybackRate(speed)
    }
    
    public func GetBuffered() -> VZBufferRange {
        let start = Int(controller?.currentPosition ?? 0)
        let end = start + Int(controller?.bufferedDuration ?? 0)
        return VZBufferRange(length: 1, start: start, end: end)
    }
    
    // MARK: - IPlayer: 事件与源
    
    public func SendEvent(_ eventName: String, params: [String: Any]?) {
        if eventName == "NEXT_SOURCE" {
            _ = switchToNextSource()
        } else if eventName == "SWITCH_SOURCE" {
            if let idx = params?["index"] as? Int ?? (params?["sourceIndex"] as? Int) {
                _ = switchToSource(index: idx)
            }
        }
    }
    
    public func getCurrentSource() -> VZPlayerSource? {
        guard currentSourceIndex >= 0 && currentSourceIndex < sources.count else {
            return nil
        }
        return sources[currentSourceIndex]
    }
    
    // MARK: - 播放源列表与策略配置
    
    public func setSources(_ sources: [VZPlayerSource]) {
        for (idx, s) in sources.enumerated() {
            s.sourceIndex = idx
        }
        self.sources = sources
        self.currentSourceIndex = 0
        self.currentEngineIndex = 0
        if let first = sources.first {
            self.engineOrder = computeEngineOrder(for: first)
        } else {
            self.engineOrder = [.avPlayer, .mePlayer]
        }
        self.needsReloadSource = true
    }
    
    public func setConfig(_ config: VZPlayerConfig) {
        self.playerConfig = config
        self.savedVolume = config.volume
        self.savedMuted = config.muted
        self.savedLoop = config.loop
        self.savedSpeed = config.speed
        
        if let ctrl = controller {
            ctrl.config.isLoop = config.loop
            ctrl.setVolume(config.volume)
            ctrl.setMute(config.muted)
            ctrl.setPlaybackRate(config.speed)
        }
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
        return IsPaused()
    }
    
    public var naturalSize: CGSize {
        return controller?.naturalSize ?? .zero
    }
    
    public func play() { Play() }
    public func pause() { Pause() }
    public func resume() { Resume() }
    public func destroy() { Destroy() }
    public func seek(to time: TimeInterval) { Seek(Int64(time)) }
    public func setVolume(_ volume: Float) { SetVolume(volume) }
    public func getVolume() -> Float { return GetVolume() }
    public func setMuted(_ isMuted: Bool) { SetMuted(isMuted) }
    public func isMuted() -> Bool { return IsMuted() }
    public func setLoop(_ loop: Bool) { SetLoop(loop) }
    public func isLoop() -> Bool { return IsLoop() }
    public func setSpeed(_ speed: Float) { SetSpeed(speed) }
    public func getSpeed() -> Float { return GetSpeed() }
    
    // MARK: - 内部容错调度
    
    private func computeEngineOrder(for source: VZPlayerSource) -> [PlayerEngineType] {
        let type = source.type.lowercased()
        let urlStr = source.url.lowercased()
        let isFlv = type == "flv" || urlStr.contains(".flv")
        let isRtmp = type == "rtmp" || urlStr.hasPrefix("rtmp://")
        let isH265 = source.videoCodec == 4 || source.tag.lowercased().contains("265") || urlStr.contains("265")
        
        if isFlv || isRtmp {
            return [.mePlayer]
        } else if isH265 {
            return [.mePlayer, .avPlayer]
        } else {
            return [.avPlayer, .mePlayer]
        }
    }
    
    private func startPlaybackWithCurrentSourceAndEngine() {
        guard !isDestroyed, let source = currentSource, let url = URL(string: source.url) else {
            let err = NSError(domain: "VZMultiSourcePlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid source URL"])
            delegate?.multiSourcePlayer(self, didOccurError: err)
            for l in eventListeners { l.onError(code: -1, errMsg: "Invalid source URL") }
            return
        }
        
        needsReloadSource = false
        let engineType = engineOrder[currentEngineIndex]
        
        // 1. 释放旧的控制器
        controller?.stop()
        controller?.delegate = nil
        playerView.detachRenderView()
        
        // 2. 创建新控制器并配置
        let config = PlayerConfig()
        config.preferredEngine = engineType
        config.enableHardwareDecode = (engineType == .avPlayer) ? playerConfig.isHardwareDecode : false
        config.isLoop = savedLoop
        config.autoPlay = true
        config.customHeaders = playerConfig.headers
        
        let ctrl = MediaPlayerController(config: config)
        ctrl.delegate = self
        self.controller = ctrl
        
        // 3. 附加视图并准备播放
        playerView.attachRenderView(ctrl.playerView.renderView)
        ctrl.prepare(with: url)
        ctrl.setVolume(savedVolume)
        ctrl.setMute(savedMuted)
        ctrl.setPlaybackRate(savedSpeed)
        
        if let s = currentSource {
            for l in eventListeners { l.onSourceSwitched(source: s) }
        }
    }
    
    private func handleRetry(error: NSError) {
        guard !isDestroyed else { return }
        
        let errorMsg = error.localizedDescription
        let isNotFound = error.code == 404 || errorMsg.contains("404") || errorMsg.contains("not found")
        
        if isNotFound {
            // 404 流不存在，跳过 Layer 1 内核重试，直接尝试 Layer 2 下一个地址
            let msg = "Stream not found (404), skip engine retry"
            delegate?.multiSourcePlayer(self, didWarnMessage: msg)
            for l in eventListeners { l.onWarnMessage(msg: msg) }
            tryNextSource(lastError: error)
            return
        }
        
        // Layer 1: 尝试下一个内核
        if currentEngineIndex + 1 < engineOrder.count {
            currentEngineIndex += 1
            let msg = "Retry with fallback engine: \(engineOrder[currentEngineIndex])"
            delegate?.multiSourcePlayer(self, didWarnMessage: msg)
            for l in eventListeners { l.onWarnMessage(msg: msg) }
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
            let nextSource = sources[currentSourceIndex]
            self.engineOrder = computeEngineOrder(for: nextSource)
            let msg = "Switch to nextSource [\(currentSourceIndex + 1)/\(sources.count)] (\(nextSource.tag))"
            delegate?.multiSourcePlayer(self, didWarnMessage: msg)
            for l in eventListeners { l.onWarnMessage(msg: msg) }
            startPlaybackWithCurrentSourceAndEngine()
        } else {
            // 所有地址和内核全部耗尽，最终上报错误
            delegate?.multiSourcePlayer(self, didOccurError: lastError)
            for l in eventListeners { l.onError(code: lastError.code, errMsg: lastError.localizedDescription) }
        }
    }
    
    public func switchToNextSource() -> Bool {
        if currentSourceIndex + 1 < sources.count {
            return switchToSource(index: currentSourceIndex + 1)
        }
        return false
    }
    
    public func switchToSource(index: Int) -> Bool {
        guard index >= 0 && index < sources.count else { return false }
        currentSourceIndex = index
        currentEngineIndex = 0
        let targetSource = sources[currentSourceIndex]
        self.engineOrder = computeEngineOrder(for: targetSource)
        let msg = "Switch to source [\(currentSourceIndex + 1)/\(sources.count)] (\(targetSource.tag))"
        delegate?.multiSourcePlayer(self, didWarnMessage: msg)
        for l in eventListeners { l.onWarnMessage(msg: msg) }
        startPlaybackWithCurrentSourceAndEngine()
        return true
    }
    
    // MARK: - MediaPlayerDelegate 代理桥接
    
    public func player(_ player: MediaPlayerController, stateDidChange state: PlayerState) {
        delegate?.multiSourcePlayer(self, stateDidChange: state)
        for l in eventListeners { l.onStateChanged(state: state) }
    }
    
    public func playerDidRenderFirstFrame(_ player: MediaPlayerController) {
        delegate?.multiSourcePlayer(self, didRenderFirstFrame: ())
        for l in eventListeners { l.onFirstFrameRendered() }
    }
    
    public func player(_ player: MediaPlayerController, currentTime: TimeInterval, totalDuration: TimeInterval) {
        delegate?.multiSourcePlayer(self, currentTime: currentTime, totalDuration: totalDuration)
        for l in eventListeners { l.onTimeUpdate(currentTime: Int64(currentTime), totalDuration: Int64(totalDuration)) }
    }
    
    public func player(_ player: MediaPlayerController, didOccurError error: NSError) {
        handleRetry(error: error)
    }
    
    public func playerDidPlayToEndTime(_ player: MediaPlayerController) {
        delegate?.multiSourcePlayerDidPlayToEnd(self)
        for l in eventListeners { l.onPlayToEnd() }
    }
}
