import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import KSPlayer

/// 基于 FFmpeg + VideoToolbox + Metal 的 KSPlayer 多媒体管线引擎
/// 全面支持 RTMP、HTTP-FLV、HLS、RTSP、MKV、MP4、DASH 全协议全格式解码
public final class KSMEPlayerEngine: NSObject, MediaPlayerProtocol {
    public weak var outputDelegate: PlayerEngineOutputDelegate?
    
    public var renderView: PlatformView {
        return playerView
    }
    
    #if canImport(UIKit)
    private let playerView = IOSVideoPlayerView()
    #elseif canImport(AppKit)
    private let playerView = MacVideoPlayerView()
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
    
    public var currentPosition: TimeInterval = 0
    public var duration: TimeInterval = 0
    public var bufferedDuration: TimeInterval {
        if let time = playerView.playerLayer?.player.playableTime, time > 0 {
            return time
        }
        return bufferedDurationValue
    }
    public var isPlaying: Bool {
        return state == .playing
    }
    public var naturalSize: CGSize {
        if let size = playerView.playerLayer?.player.naturalSize, size != .zero {
            return size
        }
        return naturalSizeValue
    }
    
    private var bufferedDurationValue: TimeInterval = 0
    private var naturalSizeValue: CGSize = .zero
    private var config: PlayerConfig = PlayerConfig()
    private var isFirstFrameRendered = false
    private var currentURL: URL?
    private var qosReport: PlayerQoSReport?
    private var savedVolume: Float = 1.0
    private var savedRate: Float = 1.0
    private var savedMuted: Bool = false
    private var savedSubtitleURL: URL?
    
    public override init() {
        super.init()
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = KSMEPlayer.self
        KSOptions.canBackgroundPlay = true
        KSOptions.isAutoPlay = true
        playerView.delegate = self
    }
    
    public func prepare(with url: URL, config: PlayerConfig) {
        self.reset()
        self.currentURL = url
        self.config = config
        self.state = .preparing
        self.isFirstFrameRendered = false
        
        let report = PlayerQoSReport(sessionID: UUID().uuidString, mediaURL: url, engineName: "KSPlayer (FFmpeg)")
        report.isHardwareAccelerated = config.enableHardwareDecode
        self.qosReport = report
        
        KSOptions.isAutoPlay = config.autoPlay
        KSOptions.isLoopPlay = config.isLoop
        KSOptions.hardwareDecode = config.enableHardwareDecode
        
        let opt = KSOptions()
        opt.hardwareDecode = config.enableHardwareDecode
        opt.isLoopPlay = config.isLoop
        opt.isSeekedAutoPlay = config.autoPlay
        opt.startPlayRate = savedRate
        
        if !config.customHeaders.isEmpty {
            var headerLines = ""
            for (k, v) in config.customHeaders {
                headerLines += "\(k): \(v)\r\n"
            }
            opt.formatContextOptions["headers"] = headerLines
        }
        
        playerView.set(url: url, options: opt)
        
        playerView.playerLayer?.player.playbackVolume = savedVolume
        playerView.playerLayer?.player.playbackRate = savedRate
        playerView.playerLayer?.player.isMuted = savedMuted
        
        if let subURL = savedSubtitleURL {
            playerView.srtControl.addSubtitle(dataSouce: SubtitleURLDataSouce(url: subURL))
        }
        
        if config.autoPlay {
            self.play()
        }
    }
    
    public func play() {
        playerView.play()
        if state == .readyToPlay || state == .paused || state == .preparing {
            state = .playing
        }
    }
    
    public func pause() {
        playerView.pause()
        if state == .playing || state == .readyToPlay || state == .preparing {
            state = .paused
        }
    }
    
    public func seek(to time: TimeInterval, completion: ((Bool) -> Void)?) {
        playerView.seek(time: time) { finished in
            completion?(finished)
        }
    }
    
    public func stop() {
        reset()
        state = .stopped
    }
    
    public func reset() {
        playerView.pause()
        playerView.resetPlayer()
        currentPosition = 0
        duration = 0
        bufferedDurationValue = 0
        naturalSizeValue = .zero
        state = .idle
        isFirstFrameRendered = false
    }
    
    public func setVolume(_ volume: Float) {
        savedVolume = volume
        playerView.playerLayer?.player.playbackVolume = volume
    }
    
    public func setPlaybackRate(_ rate: Float) {
        savedRate = rate
        playerView.playerLayer?.player.playbackRate = rate
    }
    
    public func setMute(_ isMuted: Bool) {
        savedMuted = isMuted
        playerView.playerLayer?.player.isMuted = isMuted
    }
    
    public func setLoop(_ loop: Bool) {
        config.isLoop = loop
        KSOptions.isLoopPlay = loop
        playerView.playerLayer?.options.isLoopPlay = loop
    }
    
    public func setSubtitleURL(_ url: URL?) {
        savedSubtitleURL = url
        if let subURL = url {
            playerView.srtControl.addSubtitle(dataSouce: SubtitleURLDataSouce(url: subURL))
        }
    }
    
    public func getQoSReport() -> PlayerQoSReport? {
        return qosReport
    }
}

extension KSMEPlayerEngine: PlayerControllerDelegate {
    public func playerController(state: KSPlayerState) {
        DispatchQueue.main.async {
            let mapped: PlayerState
            switch state {
            case .readyToPlay:
                mapped = self.config.autoPlay ? .playing : .readyToPlay
            case .buffering:
                mapped = .buffering
            case .bufferFinished:
                mapped = .playing
            case .paused:
                mapped = .paused
            case .playedToTheEnd:
                mapped = .completed
                self.outputDelegate?.engineDidPlayToEnd(self)
            case .error:
                mapped = .error
            default:
                mapped = .idle
            }
            self.state = mapped
        }
    }
    
    public func playerController(currentTime: TimeInterval, totalTime: TimeInterval) {
        DispatchQueue.main.async {
            self.currentPosition = currentTime
            self.duration = totalTime
            self.outputDelegate?.engine(self, currentTimeDidChange: currentTime, duration: totalTime)
            
            if !self.isFirstFrameRendered && (currentTime > 0 || self.isPlaying) {
                self.isFirstFrameRendered = true
                self.outputDelegate?.engineDidRenderFirstFrame(self)
            }
        }
    }
    
    public func playerController(finish error: Error?) {
        if let err = error as NSError? {
            DispatchQueue.main.async {
                self.state = .error
                self.outputDelegate?.engine(self, didOccurError: err)
            }
        }
    }
    
    public func playerController(maskShow: Bool) {}
    public func playerController(action: PlayerButtonType) {}
    public func playerController(bufferedCount: Int, consumeTime: TimeInterval) {}
    public func playerController(seek: TimeInterval) {}
}
