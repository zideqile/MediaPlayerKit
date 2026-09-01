import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 原生 AVFoundation / AVPlayer 引擎实现
public final class KSAVPlayerEngine: NSObject, MediaPlayerProtocol {
    public weak var outputDelegate: PlayerEngineOutputDelegate?
    
    public var renderView: PlatformView {
        return containerView
    }
    private let containerView = PlatformView()
    private var playerLayer: AVPlayerLayer?
    
    public private(set) var state: PlayerState = .idle {
        didSet {
            if oldValue != state {
                outputDelegate?.engine(self, stateDidChange: state)
            }
        }
    }
    
    public var currentPosition: TimeInterval {
        guard let player = player else { return 0 }
        return CMTimeGetSeconds(player.currentTime())
    }
    
    public var duration: TimeInterval {
        guard let currentItem = player?.currentItem else { return 0 }
        let sec = CMTimeGetSeconds(currentItem.duration)
        return sec.isNaN ? 0 : sec
    }
    
    public var bufferedDuration: TimeInterval {
        guard let currentItem = player?.currentItem,
              let timeRange = currentItem.loadedTimeRanges.first?.timeRangeValue else { return 0 }
        return CMTimeGetSeconds(CMTimeAdd(timeRange.start, timeRange.duration))
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
    private var config: PlayerConfig = PlayerConfig()
    private var isFirstFrameRendered = false
    private var currentURL: URL?
    private var qosReport: PlayerQoSReport?

    public override init() {
        super.init()
        #if canImport(UIKit)
        containerView.backgroundColor = .black
        #elseif canImport(AppKit)
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.black.cgColor
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
        
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.frame = containerView.bounds
        layer.needsDisplayOnBoundsChange = true
        
        #if canImport(UIKit)
        containerView.layer.addSublayer(layer)
        #elseif canImport(AppKit)
        containerView.layer?.addSublayer(layer)
        #endif
        self.playerLayer = layer
        
        setupObservers(for: item)
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
        removeObservers()
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
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
    
    private func setupObservers(for item: AVPlayerItem) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidPlayToEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }
    
    private func removeObservers() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.3, preferredTimescale: 600)
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let current = CMTimeGetSeconds(time)
            let total = self.duration
            self.outputDelegate?.engine(self, currentTimeDidChange: current, duration: total)
            
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
        if config.isLoop {
            seek(to: 0) { [weak self] _ in
                self?.play()
            }
        } else {
            state = .completed
            outputDelegate?.engineDidPlayToEnd(self)
        }
    }
}
