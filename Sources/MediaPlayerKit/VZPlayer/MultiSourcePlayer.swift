import Foundation
import CoreGraphics

public protocol MultiSourcePlayerDelegate: AnyObject {
    func multiSourcePlayer(_ player: MultiSourcePlayer, stateDidChange state: PlayerState)
    func multiSourcePlayer(_ player: MultiSourcePlayer, didRenderFirstFrame: Void)
    func multiSourcePlayer(_ player: MultiSourcePlayer, currentTime: TimeInterval, totalDuration: TimeInterval)
    func multiSourcePlayer(_ player: MultiSourcePlayer, didOccurError error: NSError)
    func multiSourcePlayerDidPlayToEnd(_ player: MultiSourcePlayer)
    func multiSourcePlayer(_ player: MultiSourcePlayer, didSwitchToSource source: PlayerSource)
    func multiSourcePlayer(_ player: MultiSourcePlayer, didWarnMessage msg: String)
}

private final class WeakPlayerEventListener {
    weak var value: PlayerEventListener?
    init(_ value: PlayerEventListener) {
        self.value = value
    }
}

/// 多播放源管理器与两层容错调度器 (实现 IPlayer 协议，对标 Android vzplayer 的 MultiSourcePlayer & PlayerSelector)
@objc(MultiSourcePlayer)
public final class MultiSourcePlayer: NSObject, IPlayer, MediaPlayerDelegate {
    public weak var delegate: MultiSourcePlayerDelegate?
    private var eventListeners: [WeakPlayerEventListener] = []
    
    public private(set) var sources: [PlayerSource] = []
    public private(set) var currentSourceIndex: Int = 0
    
    public var currentSource: PlayerSource? {
        return getCurrentSource()
    }
    
    // 内核尝试顺序：0: AVPlayer (硬解), 1: KSMEPlayer (软解)
    private var engineOrder: [PlayerEngineType] = [.avPlayer, .mePlayer]
    private var currentEngineIndex: Int = 0
    
    private var controller: MediaPlayerController?
    private let playerView: MediaPlayerView
    private var playerConfig: VPlayerConfig
    
    // 保存用户状态
    private var savedVolume: Float = 1.0
    private var savedMuted: Bool = false
    private var savedLoop: Bool = false
    private var savedSpeed: Float = 1.0
    private var isDestroyed: Bool = false
    private var needsReloadSource: Bool = false
    private var generation: UInt64 = 0
    private var attemptHandled = false
    private var terminalFailure = false
    private var wantsToPlay = true
    private let diagnostics = PlaybackDiagnostics()
    /// Cleared by a new explicit source list or source switch, retained across automatic recovery.
    public private(set) var failureHistory: [PlaybackAttemptFailure] = []
    
    public init(playerView: MediaPlayerView, config: VPlayerConfig = VPlayerConfig()) {
        self.playerView = playerView
        self.playerConfig = config
        self.savedVolume = config.volume
        self.savedMuted = config.muted
        self.savedLoop = config.loop
        self.savedSpeed = config.speed
        super.init()
    }
    
    // MARK: - IPlayer: 事件监听器
    
    public func AddEventListener(_ listener: PlayerEventListener?) {
        guard let l = listener else { return }
        eventListeners.removeAll(where: { $0.value == nil })
        if !eventListeners.contains(where: { $0.value === l }) {
            eventListeners.append(WeakPlayerEventListener(l))
        }
    }
    
    public func RemoveEventListener(_ listener: PlayerEventListener?) {
        guard let l = listener else { return }
        eventListeners.removeAll(where: { $0.value == nil || $0.value === l })
    }
    
    private func notifyListeners(_ action: (PlayerEventListener) -> Void) {
        eventListeners.removeAll(where: { $0.value == nil })
        let token = generation
        let listeners = eventListeners.compactMap { $0.value }
        for listener in listeners {
            guard generation == token, !isDestroyed else { break }
            action(listener)
        }
    }
    
    // MARK: - IPlayer: 基础播放控制
    
    public func Play(_ sources: [PlayerSource]) -> Bool {
        guard !isDestroyed else { return false }
        self.setSources(sources)
        self.Play()
        return !sources.isEmpty
    }
    
    public func Play() {
        guard !isDestroyed else { return }
        wantsToPlay = true
        diagnostics.command("play player")
        guard !sources.isEmpty else {
            let err = NSError(domain: "MultiSourcePlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "sources is empty"])
            controller?.delegate = nil
            controller?.stop()
            controller = nil
            playerView.detachRenderView()
            finishFailure(err)
            return
        }
        if controller == nil || needsReloadSource || terminalFailure {
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
        diagnostics.command("pause player")
        wantsToPlay = false
        controller?.config.autoPlay = false
        controller?.pause()
    }
    
    public func Resume() {
        diagnostics.command("resume player")
        wantsToPlay = true
        controller?.config.autoPlay = true
        controller?.play()
    }
    
    public func Destroy() {
        isDestroyed = true
        generation &+= 1
        controller?.delegate = nil
        controller?.stop()
        controller = nil
        eventListeners.removeAll()
        diagnostics.finish()
    }
    
    // MARK: - IPlayer: 进度与状态
    
    public func Seek(_ seconds: Int64) {
        diagnostics.command("seek to \(seconds)")
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
    
    public func GetBuffered() -> BufferRange {
        let start = Int(controller?.currentPosition ?? 0)
        // 两个引擎均返回媒体时间轴上的缓冲终点，而非剩余缓冲时长。
        let end = max(start, Int(controller?.bufferedDuration ?? 0))
        return BufferRange(length: 1, start: start, end: end)
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
    
    public func getCurrentSource() -> PlayerSource? {
        guard currentSourceIndex >= 0 && currentSourceIndex < sources.count else {
            return nil
        }
        return sources[currentSourceIndex]
    }
    
    // MARK: - 播放源列表与策略配置
    
    public func setSources(_ sources: [PlayerSource]) {
        generation &+= 1 // Cancel a queued retry, even before Play is called.
        terminalFailure = false
        failureHistory.removeAll()
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
        diagnostics.sources(sources)
    }
    
    public func setConfig(_ config: VPlayerConfig) {
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
    
    private func computeEngineOrder(for source: PlayerSource) -> [PlayerEngineType] {
        let type = source.type.lowercased()
        let urlStr = source.url.lowercased()
        let isFlv = type == "flv" || urlStr.contains(".flv")
        let isRtmp = type == "rtmp" || urlStr.hasPrefix("rtmp://")
        let isRtsp = urlStr.hasPrefix("rtsp://")
        let isH265 = source.videoCodec == PlayerSource.CODEC_H265 || source.videoCodec == 4 || source.tag.lowercased().contains("265") || urlStr.contains("265")
        
        if isFlv || isRtmp || isRtsp {
            return [.mePlayer]
        } else if isH265 {
            return [.mePlayer, .avPlayer]
        } else {
            return [.avPlayer, .mePlayer]
        }
    }
    
    private func startPlaybackWithCurrentSourceAndEngine() {
        guard !isDestroyed else { return }
        generation &+= 1
        let token = generation
        attemptHandled = false
        terminalFailure = false
        needsReloadSource = false
        controller?.delegate = nil
        controller?.stop()
        controller = nil
        playerView.detachRenderView()
        guard let source = currentSource else { return }
        diagnostics.begin(source: source, engine: engineOrder[currentEngineIndex])
        guard let url = URL(string: source.url), let scheme = url.scheme, !scheme.isEmpty else {
            handleRetry(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL,
                userInfo: [NSLocalizedDescriptionKey: "Invalid source URL"]))
            return
        }
        let engineType = engineOrder[currentEngineIndex]

        // 2. 创建新控制器并配置
        let config = MediaPlayerKit.PlayerConfig()
        config.preferredEngine = engineType
        config.enableHardwareDecode = (engineType == .avPlayer) ? playerConfig.isHardwareDecode : false
        config.isLoop = savedLoop
        config.autoPlay = wantsToPlay
        config.customHeaders = playerConfig.headers
        
        let ctrl = MediaPlayerController(config: config)
        ctrl.delegate = self
        self.controller = ctrl
        
        // 3. 附加视图并准备播放
        playerView.attachRenderView(ctrl.playerView)
        ctrl.setMediaSource(url: url)
        ctrl.setVolume(savedVolume)
        ctrl.setMute(savedMuted)
        ctrl.setPlaybackRate(savedSpeed)
        
        if generation == token, !attemptHandled, !isDestroyed {
            delegate?.multiSourcePlayer(self, didSwitchToSource: source)
            guard generation == token, !isDestroyed else { return }
            notifyListeners { $0.onSourceSwitched(source: source) }
        }
    }
    
    private func handleRetry(error: NSError) {
        guard !isDestroyed, !attemptHandled, !needsReloadSource else { return }
        attemptHandled = true
        let token = generation
        let category = PlaybackErrorAdapters.classify(error)
        let action = PlaybackRecoveryPolicy.action(for: category,
            hasNextEngine: currentEngineIndex + 1 < engineOrder.count,
            hasNextSource: currentSourceIndex + 1 < sources.count)
        let failure = PlaybackAttemptFailure(sourceIndex: currentSourceIndex,
            sourceURL: currentSource?.url ?? "", engine: engineOrder[currentEngineIndex],
            category: category, error: error, action: action)
        failureHistory.append(failure)
        diagnostics.failed(failure)
        notifyListeners { $0.onPlayAttemptFailed?(failure) }
        guard generation == token, !isDestroyed else { return }
        if action == .stop {
            finishFailure(error)
            return
        }
        notifyListeners { $0.onRecoveryStarted?(failure) }
        guard generation == token, !isDestroyed else { return }
        let message = action == .nextEngine ? "Retry with fallback engine" : "Switch to next source"
        delegate?.multiSourcePlayer(self, didWarnMessage: message)
        guard generation == token, !isDestroyed else { return }
        notifyListeners { $0.onWarnMessage(msg: message) }
        // Avoid recursive error/creation chains, and let user commands invalidate queued work.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isDestroyed, self.generation == token else { return }
            if action == .nextEngine {
                self.currentEngineIndex += 1
            } else {
                self.currentSourceIndex += 1
                self.currentEngineIndex = 0
                self.engineOrder = self.computeEngineOrder(for: self.sources[self.currentSourceIndex])
            }
            self.startPlaybackWithCurrentSourceAndEngine()
        }
    }

    private func finishFailure(_ error: NSError) {
        guard !terminalFailure, !isDestroyed else { return }
        terminalFailure = true
        diagnostics.terminal(error)
        attemptHandled = true
        let token = generation
        delegate?.multiSourcePlayer(self, stateDidChange: .error)
        guard generation == token, !isDestroyed else { return }
        notifyListeners { $0.onStateChanged(state: .error) }
        guard generation == token, !isDestroyed else { return }
        delegate?.multiSourcePlayer(self, didOccurError: error)
        guard generation == token, !isDestroyed else { return }
        notifyListeners { $0.onError(code: error.code, errMsg: error.localizedDescription) }
    }

    public func switchToNextSource() -> Bool {
        if currentSourceIndex + 1 < sources.count {
            return switchToSource(index: currentSourceIndex + 1)
        }
        return false
    }
    
    public func switchToSource(index: Int) -> Bool {
        guard !isDestroyed, index >= 0 && index < sources.count else { return false }
        generation &+= 1
        let token = generation
        failureHistory.removeAll()
        currentSourceIndex = index
        currentEngineIndex = 0
        let targetSource = sources[currentSourceIndex]
        self.engineOrder = computeEngineOrder(for: targetSource)
        diagnostics.command("switch source to index \(index)")
        let msg = "Switch to source [\(currentSourceIndex + 1)/\(sources.count)] (\(targetSource.tag))"
        delegate?.multiSourcePlayer(self, didWarnMessage: msg)
        guard generation == token, !isDestroyed else { return false }
        notifyListeners { $0.onWarnMessage(msg: msg) }
        guard generation == token, !isDestroyed else { return false }
        startPlaybackWithCurrentSourceAndEngine()
        return true
    }
    
    // MARK: - MediaPlayerDelegate 代理桥接
    
    public func player(_ player: MediaPlayerController, stateDidChange state: PlayerState) {
        guard player === controller, !isDestroyed, !needsReloadSource, !attemptHandled else { return }
        // An engine error is an attempt failure, not yet a terminal player error.
        guard state != .error else { return }
        diagnostics.state(state)
        let token = generation
        delegate?.multiSourcePlayer(self, stateDidChange: state)
        guard generation == token, !isDestroyed else { return }
        notifyListeners { $0.onStateChanged(state: state) }
    }
    
    public func playerDidRenderFirstFrame(_ player: MediaPlayerController) {
        guard player === controller, !isDestroyed, !needsReloadSource, !attemptHandled else { return }
        let token = generation
        diagnostics.firstFrame(size: player.naturalSize)
        delegate?.multiSourcePlayer(self, didRenderFirstFrame: ())
        guard generation == token, !isDestroyed else { return }
        notifyListeners { $0.onFirstFrameRendered() }
    }
    
    public func player(_ player: MediaPlayerController, currentTime: TimeInterval, totalDuration: TimeInterval) {
        guard player === controller, !isDestroyed, !needsReloadSource, !attemptHandled else { return }
        let token = generation
        diagnostics.sampleMetrics(interval: Double(playerConfig.runtimeStateCollect.collectIntervalSeconds)) {
            player.runtimeMetrics
        }
        delegate?.multiSourcePlayer(self, currentTime: currentTime, totalDuration: totalDuration)
        guard generation == token, !isDestroyed else { return }
        notifyListeners { $0.onTimeUpdate(currentTime: Int64(currentTime), totalDuration: Int64(totalDuration)) }
    }
    
    public func player(_ player: MediaPlayerController, didOccurError error: NSError) {
        guard player === controller, !isDestroyed, !needsReloadSource, !attemptHandled else { return }
        handleRetry(error: error)
    }
    
    public func playerDidPlayToEndTime(_ player: MediaPlayerController) {
        guard player === controller, !isDestroyed, !needsReloadSource, !attemptHandled else { return }
        let token = generation
        diagnostics.command("player is eof")
        delegate?.multiSourcePlayerDidPlayToEnd(self)
        guard generation == token, !isDestroyed else { return }
        notifyListeners { $0.onPlayToEnd() }
    }
}
