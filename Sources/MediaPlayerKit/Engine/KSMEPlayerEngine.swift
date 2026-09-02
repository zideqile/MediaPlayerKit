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
                DispatchQueue.main.async {
                    self.outputDelegate?.engine(self, stateDidChange: self.state)
                }
            }
        }
    }
    
    public var currentPosition: TimeInterval = 0
    public var duration: TimeInterval = 0
    public var bufferedDuration: TimeInterval = 0
    public var isPlaying: Bool {
        return state == .playing
    }
    public var naturalSize: CGSize = .zero
    
    private var config: PlayerConfig = PlayerConfig()
    private var isFirstFrameRendered = false
    private var currentURL: URL?
    private var qosReport: PlayerQoSReport?
    
    public override init() {
        super.init()
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = KSMEPlayer.self
        KSOptions.canBackgroundPlay = true
        #if canImport(UIKit)
        playerView.delegate = self
        playerView.toolBar.isHidden = true
        #elseif canImport(AppKit)
        playerView.delegate = self
        #endif
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
        
        let opt = KSOptions()
        opt.isAutoPlay = config.autoPlay
        opt.isLoopPlay = config.isLoop
        
        #if canImport(UIKit)
        playerView.set(url: url, options: opt)
        #elseif canImport(AppKit)
        playerView.set(url: url, options: opt)
        #endif
        
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
        playerView.seek(time: time)
        completion?(true)
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
        bufferedDuration = 0
        state = .idle
        isFirstFrameRendered = false
    }
    
    public func setVolume(_ volume: Float) {}
    public func setPlaybackRate(_ rate: Float) {
        playerView.playbackRate = rate
    }
    public func setMute(_ isMuted: Bool) {}
    public func setSubtitleURL(_ url: URL?) {}
    
    public func getQoSReport() -> PlayerQoSReport? {
        return qosReport
    }
}

#if canImport(UIKit)
extension KSMEPlayerEngine: PlayerControllerDelegate {
    public func playerController(state: KSPlayerState) {
        DispatchQueue.main.async {
            let mapped: PlayerState
            switch state {
            case .readyToPlay:
                mapped = self.config.autoPlay ? .playing : .readyToPlay
                if !self.isFirstFrameRendered {
                    self.isFirstFrameRendered = true
                    self.outputDelegate?.engineDidRenderFirstFrame(self)
                }
            case .buffering:
                mapped = .buffering
            case .bufferFinished:
                mapped = .playing
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
}
#elseif canImport(AppKit)
extension KSMEPlayerEngine: PlayerControllerDelegate {
    public func playerController(state: KSPlayerState) {
        DispatchQueue.main.async {
            let mapped: PlayerState
            switch state {
            case .readyToPlay:
                mapped = self.config.autoPlay ? .playing : .readyToPlay
                if !self.isFirstFrameRendered {
                    self.isFirstFrameRendered = true
                    self.outputDelegate?.engineDidRenderFirstFrame(self)
                }
            case .buffering:
                mapped = .buffering
            case .bufferFinished:
                mapped = .playing
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
}
#endif
