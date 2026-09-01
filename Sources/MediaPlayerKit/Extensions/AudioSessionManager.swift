import Foundation
import AVFoundation

/// 系统级音频会话调度中心
/// 统一管理后台播放、电话打断恢复、耳机拔出暂停与混音策略 (针对 iOS / tvOS / visionOS)
public final class AudioSessionManager {
    public static let shared = AudioSessionManager()
    
    private init() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        setupObservers()
        #endif
    }
    
    /// 激活播放器音频会话 (支持后台播放)
    public func activatePlaybackSession() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[MediaPlayerKit AudioSession] Activate failed: \(error)")
        }
        #endif
    }
    
    /// 释放音频会话
    public func deactivateSession() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
    
    #if os(iOS) || os(tvOS) || os(visionOS)
    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            NotificationCenter.default.post(name: .MediaPlayerAudioInterruptionBegan, object: nil)
        case .ended:
            NotificationCenter.default.post(name: .MediaPlayerAudioInterruptionEnded, object: nil)
        @unknown default:
            break
        }
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        if reason == .oldDeviceUnavailable {
            NotificationCenter.default.post(name: .MediaPlayerHeadphonesUnplugged, object: nil)
        }
    }
    #endif
}

public extension Notification.Name {
    static let MediaPlayerAudioInterruptionBegan = Notification.Name("MediaPlayerAudioInterruptionBegan")
    static let MediaPlayerAudioInterruptionEnded = Notification.Name("MediaPlayerAudioInterruptionEnded")
    static let MediaPlayerHeadphonesUnplugged = Notification.Name("MediaPlayerHeadphonesUnplugged")
}
