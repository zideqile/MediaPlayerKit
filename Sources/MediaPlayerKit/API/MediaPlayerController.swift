import Foundation
import CoreGraphics

/// 播放器对外统一门面控制器 (Facade - 兼容 iOS, macOS, tvOS, visionOS)
@objc public final class MediaPlayerController: NSObject, PlayerEngineOutputDelegate {
    /// 事件与状态回调代理
    @objc public weak var delegate: MediaPlayerDelegate?
    
    /// 播放器渲染视图
    @objc public let playerView: MediaPlayerView
    
    /// 当前播放状态
    @objc public var state: PlayerState {
        return engine.state
    }
    
    /// 当前播放时间进度 (秒)
    @objc public var currentPosition: TimeInterval {
        return engine.currentPosition
    }
    
    /// 媒体总时长 (秒)
    @objc public var duration: TimeInterval {
        return engine.duration
    }
    
    /// 当前已缓存/已缓冲时长 (秒)
    @objc public var bufferedDuration: TimeInterval {
        return engine.bufferedDuration
    }
    
    /// 当前是否正在播放
    @objc public var isPlaying: Bool {
        return engine.isPlaying
    }
    
    /// 媒体自然分辨率
    @objc public var naturalSize: CGSize {
        return engine.naturalSize
    }
    
    /// 当前配置
    @objc public var config: PlayerConfig
    
    private var engine: MediaPlayerProtocol
    private var apmTracker: QoSAPMTracker?
    private var currentURL: URL?

    // MARK: - 初始化
    @objc public init(config: PlayerConfig = PlayerConfig.defaultConfig()) {
        self.config = config
        self.playerView = MediaPlayerView()
        
        switch config.preferredEngine {
        case .avPlayer, .auto:
            self.engine = KSAVPlayerEngine()
        case .mePlayer:
            self.engine = KSMEPlayerEngine()
        }
        
        super.init()
        self.setupEngine()
        AudioSessionManager.shared.activatePlaybackSession()
    }
    
    private func setupEngine() {
        self.engine.outputDelegate = self
        self.playerView.attachRenderView(self.engine.renderView)
    }
    
    /// 动态切换底层播放引擎
    @objc public func switchEngine(to engineType: PlayerEngineType) {
        let wasPlaying = self.isPlaying
        let pos = self.currentPosition
        let url = self.currentURL
        
        self.stop()
        self.playerView.detachRenderView()
        
        self.config.preferredEngine = engineType
        switch engineType {
        case .avPlayer, .auto:
            self.engine = KSAVPlayerEngine()
        case .mePlayer:
            self.engine = KSMEPlayerEngine()
        }
        
        self.setupEngine()
        
        if let mediaURL = url {
            self.setMediaSource(url: mediaURL)
            if pos > 0 {
                self.seek(to: pos)
            }
            if wasPlaying {
                self.play()
            }
        }
    }
    
    // MARK: - 核心播放控制 API
    
    /// 设置媒体源 URL 并开始加载准备
    @objc public func setMediaSource(url: URL) {
        self.currentURL = url
        
        let playURL: URL
        if config.enableLocalCache {
            playURL = LocalPreloadProxy.shared.proxyURL(for: url)
        } else {
            playURL = url
        }
        
        let sessionID = UUID().uuidString
        let engineName = (engine is KSMEPlayerEngine) ? "KSMEPlayer" : "AVPlayer"
        apmTracker = QoSAPMTracker(sessionID: sessionID, mediaURL: url, engineName: engineName)
        apmTracker?.markPrepareStart()
        
        engine.prepare(with: playURL, config: config)
    }
    
    /// 开始播放
    @objc public func play() {
        apmTracker?.markPlayStart()
        engine.play()
    }
    
    /// 暂停播放
    @objc public func pause() {
        engine.pause()
    }
    
    /// 精准跳转至指定时间点 (秒)
    @objc public func seek(to time: TimeInterval, completion: ((Bool) -> Void)? = nil) {
        engine.seek(to: time, completion: completion)
    }
    
    /// 停止播放并释放解码资源
    @objc public func stop() {
        if let report = apmTracker?.finish() {
            delegate?.player?(self, didGenerateQoSReport: report)
        }
        engine.stop()
    }
    
    /// 针对短视频 Feed 列表滑动时的轻量化重置 (不销毁实例，保留预热)
    @objc public func reset() {
        engine.reset()
    }
    
    /// 设置播放音量 (0.0 ~ 1.0)
    @objc public func setVolume(_ volume: Float) {
        engine.setVolume(volume)
    }
    
    /// 设置倍速播放 (0.5x ~ 2.0x)
    @objc public func setPlaybackRate(_ rate: Float) {
        engine.setPlaybackRate(rate)
    }
    
    /// 设置静音
    @objc public func setMute(_ isMuted: Bool) {
        engine.setMute(isMuted)
    }
    
    /// 挂载外部字幕源 (ASS / SSA / WebVTT / SRT)
    @objc public func setSubtitleSource(url: URL?) {
        engine.setSubtitleURL(url)
    }
    
    /// 获取当前播放会话的 QoS 度量报告
    @objc public func currentQoSReport() -> PlayerQoSReport? {
        return apmTracker?.finish() ?? engine.getQoSReport()
    }
    
    // MARK: - 引擎回调内部路由 (PlayerEngineOutputDelegate)
    
    public func engine(_ engine: MediaPlayerProtocol, stateDidChange state: PlayerState) {
        if state == .buffering {
            apmTracker?.markBufferingStart()
        } else if state == .playing {
            apmTracker?.markBufferingEnd()
        }
        delegate?.player(self, stateDidChange: state)
    }
    
    public func engine(_ engine: MediaPlayerProtocol, currentTimeDidChange currentTime: TimeInterval, duration: TimeInterval) {
        delegate?.player(self, currentTime: currentTime, totalDuration: duration)
    }
    
    public func engineDidRenderFirstFrame(_ engine: MediaPlayerProtocol) {
        apmTracker?.markFirstFrameRendered()
        delegate?.playerDidRenderFirstFrame(self)
    }
    
    public func engine(_ engine: MediaPlayerProtocol, didOccurError error: NSError) {
        apmTracker?.markError(code: error.code, message: error.localizedDescription)
        delegate?.player(self, didOccurError: error)
    }
    
    public func engine(_ engine: MediaPlayerProtocol, bufferedDurationDidChange duration: TimeInterval) {
        delegate?.player?(self, bufferedDuration: duration)
    }
    
    public func engineDidPlayToEnd(_ engine: MediaPlayerProtocol) {
        delegate?.playerDidPlayToEndTime?(self)
    }
}

// MARK: - 现代 Swift Concurrency 协程支持扩展
extension MediaPlayerController {
    /// 异步跳转至目标时间
    @discardableResult
    public func seek(to time: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            self.seek(to: time) { finished in
                continuation.resume(returning: finished)
            }
        }
    }
}
