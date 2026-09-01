import Foundation
#if canImport(UIKit)
import UIKit
public typealias PlatformView = UIView
#elseif canImport(AppKit)
import AppKit
public typealias PlatformView = NSView
#endif
import CoreMedia

/// 内核引擎事件回调协议
public protocol PlayerEngineOutputDelegate: AnyObject {
    func engine(_ engine: MediaPlayerProtocol, stateDidChange state: PlayerState)
    func engine(_ engine: MediaPlayerProtocol, currentTimeDidChange currentTime: TimeInterval, duration: TimeInterval)
    func engineDidRenderFirstFrame(_ engine: MediaPlayerProtocol)
    func engine(_ engine: MediaPlayerProtocol, didOccurError error: NSError)
    func engine(_ engine: MediaPlayerProtocol, bufferedDurationDidChange duration: TimeInterval)
    func engineDidPlayToEnd(_ engine: MediaPlayerProtocol)
}

/// 播放器内核抽象协议 (支持 iOS / macOS / tvOS / visionOS 全平台)
public protocol MediaPlayerProtocol: AnyObject {
    var outputDelegate: PlayerEngineOutputDelegate? { get set }
    var renderView: PlatformView { get }
    
    var state: PlayerState { get }
    var currentPosition: TimeInterval { get }
    var duration: TimeInterval { get }
    var bufferedDuration: TimeInterval { get }
    var isPlaying: Bool { get }
    var naturalSize: CGSize { get }
    
    func prepare(with url: URL, config: PlayerConfig)
    func play()
    func pause()
    func seek(to time: TimeInterval, completion: ((Bool) -> Void)?)
    func stop()
    func reset()
    
    func setVolume(_ volume: Float)
    func setPlaybackRate(_ rate: Float)
    func setMute(_ isMuted: Bool)
    
    func setSubtitleURL(_ url: URL?)
    func getQoSReport() -> PlayerQoSReport?
}
