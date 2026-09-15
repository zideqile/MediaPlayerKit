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
    public var requestEventHandler: ((PlayerRequestEvent) -> Void)?
    private var requestTask: Task<Void, Never>?
    private var errorEventCount = 0
    public var requestScope: String {
        #if compiler(>=6.0)
        if #available(iOS 18, macOS 15, tvOS 18, visionOS 2, *) { return "hlsRequests" }
        #endif
        return "errorLog"
    }
    
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
                let currentState = self.state
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.outputDelegate?.engine(self, stateDidChange: currentState)
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
    
    public var runtimeMetrics: PlayerRuntimeMetrics? {
        guard let item = player?.currentItem else { return nil }
        var metrics = PlayerRuntimeMetrics()
        if let track = item.tracks.compactMap({ $0.assetTrack }).first(where: { $0.mediaType == .video }),
           track.nominalFrameRate > 0 {
            metrics.nominalFrameRate = Double(track.nominalFrameRate)
        }
        if let events = item.accessLog()?.events, !events.isEmpty {
            // Access-log totals span events; they are not TS/M3U8 request-level timings.
            func sum(_ values: [Int64]) -> Int64? {
                guard values.allSatisfy({ $0 >= 0 }) else { return nil }
                var total: Int64 = 0
                for value in values {
                    let (next, overflow) = total.addingReportingOverflow(value)
                    guard !overflow else { return nil }
                    total = next
                }
                return total
            }
            metrics.networkBytes = sum(events.map { $0.numberOfBytesTransferred })
            metrics.droppedVideoFrames = sum(events.map { Int64($0.numberOfDroppedVideoFrames) })
            metrics.mediaRequests = sum(events.map { Int64($0.numberOfMediaRequests) })
            metrics.observedBitrate = events.last?.observedBitrate
        }
        return metrics
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
    private var savedPlaybackRate: Float = 1.0

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
        observeRequests(item)
        
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
        if savedPlaybackRate != 1.0 {
            player.rate = savedPlaybackRate
        }
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
        requestTask?.cancel(); requestTask = nil
        errorEventCount = 0
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
        savedPlaybackRate = 1.0
    }
    
    public func setVolume(_ volume: Float) {
        player?.volume = volume
    }
    
    public func setPlaybackRate(_ rate: Float) {
        savedPlaybackRate = rate
        if isPlaying {
            player?.rate = rate
        }
    }
    
    public func setMute(_ isMuted: Bool) {
        player?.isMuted = isMuted
    }
    
    public func setLoop(_ loop: Bool) {
        config.isLoop = loop
        player?.actionAtItemEnd = loop ? .none : .pause
    }
    
    public func setSubtitleURL(_ url: URL?) {}
    
    public func getQoSReport() -> PlayerQoSReport? {
        return qosReport
    }
    

    private func observeRequests(_ item: AVPlayerItem) {
        #if compiler(>=6.0)
        if #available(iOS 18, macOS 15, tvOS 18, visionOS 2, *) {
            let events = item.allMetrics()
            requestTask = Task { @MainActor [weak self, weak item] in
                for await event in events {
                    guard !Task.isCancelled, let self = self, let item = item,
                          self.playerItem === item else { break }
                    if let segment = event as? AVMetricHLSMediaSegmentRequestEvent,
                       let resource = segment.mediaResourceRequestEvent {
                        self.collectRequest(resource, kind: "segment")
                    } else if let playlist = event as? AVMetricHLSPlaylistRequestEvent,
                              let resource = playlist.mediaResourceRequestEvent {
                        self.collectRequest(resource, kind: "playlist")
                    } else if let key = event as? AVMetricContentKeyRequestEvent,
                              let resource = key.mediaResourceRequestEvent {
                        self.collectRequest(resource, kind: "key")
                    }
                }
            }
            return
        }
        #endif
        NotificationCenter.default.addObserver(self, selector: #selector(requestErrorLogChanged(_:)),
                                              name: .AVPlayerItemNewErrorLogEntry, object: item)
    }

    @objc private func requestErrorLogChanged(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem else { return }
        DispatchQueue.main.async { [weak self, weak item] in
            guard let self = self, let item = item, self.playerItem === item else { return }
            self.collectRequestErrors(item)
        }
    }

    private func collectRequestErrors(_ item: AVPlayerItem) {
        guard playerItem === item else { return }
        let events = item.errorLog()?.events ?? []
        if events.count < errorEventCount { errorEventCount = 0 }
        let fresh = events.dropFirst(errorEventCount)
        errorEventCount = events.count
        for event in fresh {
            guard let url = event.uri else { continue }
            // An AV error code is not necessarily an HTTP response status.
            requestEventHandler?(PlayerRequestEvent(url: url,
                endAt: event.date.map { $0.timeIntervalSince1970 * 1000 },
                errorCode: event.errorStatusCode, errorDomain: event.errorDomain))
        }
    }

    #if compiler(>=6.0)
    @available(iOS 18, macOS 15, tvOS 18, visionOS 2, *)
    private func collectRequest(_ resource: AVMetricMediaResourceRequestEvent, kind: String) {
        guard let url = resource.url else { return }
        let transactions = resource.networkTransactionMetrics?.transactionMetrics ?? []
        let last = transactions.last
        let error = resource.errorEvent.map { $0.error as NSError }
        let start = resource.requestStartTime.timeIntervalSince1970 * 1000
        let end = resource.responseEndTime.timeIntervalSince1970 * 1000
        requestEventHandler?(PlayerRequestEvent(url: url.absoluteString,
            startAt: start, endAt: end, elapsed: end >= start ? end - start : nil,
            size: last.map { $0.countOfResponseBodyBytesReceived },
            status: (last?.response as? HTTPURLResponse)?.statusCode,
            kind: kind, cached: resource.wasReadFromCache,
            errorCode: error?.code, errorDomain: error?.domain))
    }
    #endif

    deinit { requestTask?.cancel(); NotificationCenter.default.removeObserver(self) }

    private func setupKVO(for item: AVPlayerItem, player: AVPlayer) {
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard self.playerItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    if self.state == .preparing {
                        self.state = self.config.autoPlay ? .playing : .readyToPlay
                    }
                    if self.config.autoPlay {
                        self.player?.play()
                        if self.savedPlaybackRate != 1.0 {
                            self.player?.rate = self.savedPlaybackRate
                        }
                    }
                case .failed:
                    if self.requestScope == "errorLog" { self.collectRequestErrors(item) }
                    self.state = .error
                    let err = item.error as NSError? ?? NSError(domain: "MediaPlayerKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "播放加载失败"])
                    var info = err.userInfo
                    if let status = item.errorLog()?.events.last?.errorStatusCode, (400...599).contains(status) {
                        info[PlaybackErrorClassifier.httpStatusKey] = status
                    }
                    let reported = NSError(domain: err.domain, code: err.code, userInfo: info)
                    self.outputDelegate?.engine(self, didOccurError: reported)
                default:
                    break
                }
            }
        }
        
        timeControlStatusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch player.timeControlStatus {
                case .waitingToPlayAtSpecifiedRate:
                    if self.state == .playing {
                        self.state = .buffering
                    }
                case .playing:
                    if self.state == .buffering || self.state == .readyToPlay || self.state == .preparing {
                        self.state = .playing
                    }
                case .paused:
                    if self.state != .completed && self.state != .idle && self.state != .stopped && self.state != .error {
                        self.state = .paused
                    }
                @unknown default:
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
            
            if !self.isFirstFrameRendered && (current > 0 || (self.player?.rate ?? 0) > 0) {
                self.isFirstFrameRendered = true
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
