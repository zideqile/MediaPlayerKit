import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit

public final class KSAVPlayerView: UIView {
    public override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
    public var playerLayer: AVPlayerLayer {
        return self.layer as! AVPlayerLayer
    }
}
#elseif canImport(AppKit)
import AppKit

public final class KSAVPlayerView: NSView {
    public var playerLayer: AVPlayerLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let l = playerLayer {
                l.frame = self.bounds
                l.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
                self.layer?.addSublayer(l)
            }
        }
    }
    public override func layout() {
        super.layout()
        playerLayer?.frame = self.bounds
    }
}
#endif

/// 原生 AVFoundation / AVPlayer 工业级高性能引擎实现
public final class KSAVPlayerEngine: NSObject, MediaPlayerProtocol {
    public weak var outputDelegate: PlayerEngineOutputDelegate?
    
    public var renderView: PlatformView {
        return playerView
    }
    
    #if canImport(UIKit)
    private let playerView = KSAVPlayerView()
    #elseif canImport(AppKit)
    private let playerView = KSAVPlayerView()
    #endif
    
    public private(set) var state: PlayerState = .idle {
        didSet {
            if oldValue != state {
                DispatchQueue.main.async {
                    self.outputDelegate?.engine(self, stateDidChange: self.state)
                }
            }
        }
    }
    
    public var currentPosition: TimeInterval {
        guard let player = player else { return 0 }
        let sec = CMTimeGetSeconds(player.currentTime())
        return sec.isNaN || sec.isInfinite ? 0 : sec
    }
    
    public var duration: TimeInterval {
        guard let currentItem = player?.currentItem else { return 0 }
        let sec = CMTimeGetSeconds(currentItem.duration)
        return sec.isNaN || sec.isInfinite ? 0 : sec
    }
    
    public var bufferedDuration: TimeInterval {
        guard let currentItem = player?.currentItem,
              let timeRange = currentItem.loadedTimeRanges.first?.timeRangeValue else { return 0 }
        let sec = CMTimeGetSeconds(CMTimeAdd(timeRange.start, timeRange.duration))
        return sec.isNaN || sec.isInfinite ? 0 : sec
    }
    
    public var isPlaying: Bool {
        return player?.rate != 0 && player?.error == nil
    }
    
    public var naturalSize: CGSize {
        return player?.currentItem?.presentationSize ?? .zero
    }
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserverToken: Any?
    private var itemStatusObserver: NSKeyValueObservation?
    private var timeControlStatusObserver: NSKeyValueObservation?
    private var loadedTimeRangesObserver: NSKeyValueObservation?
    private var config: PlayerConfig = PlayerConfig()
    private var isFirstFrameRendered = false
    private var currentURL: URL?
    private var qosReport: PlayerQoSReport?

    public override init() {
        super.init()
        #if canImport(UIKit)
        playerView.backgroundColor = .black
        playerView.playerLayer.videoGravity = .resizeAspect
        #elseif canImport(AppKit)
        playerView.wantsLayer = true
        playerView.layer?.backgroundColor = NSColor.black.cgColor
        #endif
    }
    
    public func prepare(with url: URL, config: PlayerConfig) {
        self.reset()
        self.currentURL = url
        self.config = config
        self.state = .preparing
        self.isFirstFrameRendered = false
        
        self.qosReport = PlayerQoSReport(sessionID: UUID().uuidString, mediaURL: url, engineName: "AVPlayer")
        
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": config.customHeaders])
        let item = AVPlayerItem(asset: asset)
        self.playerItem = item
        
        let player = AVPlayer(playerItem: item)
        self.player = player
        player.actionAtItemEnd = config.isLoop ? .none : .pause
        
        #if canImport(UIKit)
        playerView.playerLayer.player = player
        #elseif canImport(AppKit)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        playerView.playerLayer = layer
        #endif
        
        setupKVO(for: item, player: player)
        setupTimeObserver()
    }
    
    public func play() {
        guard let player = player else { return }
        player.play()
        if state == .readyToPlay || state == .paused || state == .preparing {
            state = .playing
        }
    }
    
    public func pause() {
        player?.pause()
        if state == .playing || state == .readyToPlay || state == .preparing {
            state = .paused
        }
    }
    
    public func seek(to time: TimeInterval, completion: ((Bool) -> Void)?) {
        guard let player = player else {
            completion?(false)
            return
        }
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            if finished {
                guard let self = self else { return }
                self.outputDelegate?.engine(self, currentTimeDidChange: time, duration: self.duration)
            }
            completion?(finished)
        }
    }
    
    public func stop() {
        reset()
        state = .stopped
    }
    
    public func reset() {
        removeKVO()
        player?.pause()
        #if canImport(UIKit)
        playerView.playerLayer.player = nil
        #elseif canImport(AppKit)
        playerView.playerLayer = nil
        #endif
        playerItem = nil
        player = nil
        state = .idle
        isFirstFrameRendered = false
    }
    
    public func setVolume(_ volume: Float) {
        player?.volume = volume
    }
    
    public func setPlaybackRate(_ rate: Float) {
        player?.rate = rate
    }
    
    public func setMute(_ isMuted: Bool) {
        player?.isMuted = isMuted
    }
    
    public func setSubtitleURL(_ url: URL?) {}
    
    public func getQoSReport() -> PlayerQoSReport? {
        return qosReport
    }
    
    private func setupKVO(for item: AVPlayerItem, player: AVPlayer) {
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    if self.state == .preparing {
                        self.state = self.config.autoPlay ? .playing : .readyToPlay
                    }
                    if self.config.autoPlay {
                        self.player?.play()
                    }
                    if !self.isFirstFrameRendered {
                        self.isFirstFrameRendered = true
                        self.outputDelegate?.engineDidRenderFirstFrame(self)
                    }
                case .failed:
                    self.state = .error
                    let err = item.error as NSError? ?? NSError(domain: "MediaPlayerKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "播放加载失败"])
                    self.outputDelegate?.engine(self, didOccurError: err)
                default:
                    break
                }
            }
        }
        
        loadedTimeRangesObserver = item.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            let buf = self.bufferedDuration
            DispatchQueue.main.async {
                self.outputDelegate?.engine(self, bufferedDurationDidChange: buf)
            }
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidPlayToEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }
    
    private func removeKVO() {
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        timeControlStatusObserver?.invalidate()
        timeControlStatusObserver = nil
        loadedTimeRangesObserver?.invalidate()
        loadedTimeRangesObserver = nil
        
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let current = CMTimeGetSeconds(time)
            let total = self.duration
            if !current.isNaN && !current.isInfinite {
                self.outputDelegate?.engine(self, currentTimeDidChange: current, duration: total)
            }
            
            if !self.isFirstFrameRendered && current > 0 {
                self.isFirstFrameRendered = true
                if self.state != .paused {
                    self.state = self.config.autoPlay ? .playing : .readyToPlay
                }
                self.outputDelegate?.engineDidRenderFirstFrame(self)
            }
        }
    }
    
    @objc private func itemDidPlayToEnd() {
        DispatchQueue.main.async {
            if self.config.isLoop {
                self.seek(to: 0) { [weak self] _ in
                    self?.play()
                }
            } else {
                self.state = .completed
                self.outputDelegate?.engineDidPlayToEnd(self)
            }
        }
    }
}
