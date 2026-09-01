import Foundation
import AVKit
import AVFoundation
import CoreMedia

/// 系统级原生画中画 (Picture-in-Picture) 控制器
public final class PiPController: NSObject, AVPictureInPictureControllerDelegate {
    private var pipController: AVPictureInPictureController?
    
    public var isPictureInPictureSupported: Bool {
        return AVPictureInPictureController.isPictureInPictureSupported()
    }
    
    public var isPictureInPictureActive: Bool {
        return pipController?.isPictureInPictureActive ?? false
    }
    
    public override init() {
        super.init()
    }
    
    #if canImport(UIKit) && !os(watchOS)
    /// 针对 AVPlayerLayer 初始化画中画
    public func setup(with playerLayer: AVPlayerLayer) {
        guard isPictureInPictureSupported else { return }
        pipController = AVPictureInPictureController(playerLayer: playerLayer)
        pipController?.delegate = self
    }
    
    /// 针对 AVSampleBufferDisplayLayer (Metal/硬解分支) 初始化画中画
    @available(iOS 15.0, tvOS 15.0, macOS 12.0, *)
    public func setup(with sampleBufferLayer: AVSampleBufferDisplayLayer) {
        guard isPictureInPictureSupported else { return }
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: sampleBufferLayer,
            playbackDelegate: self
        )
        pipController = AVPictureInPictureController(contentSource: contentSource)
        pipController?.delegate = self
    }
    #endif
    
    public func startPictureInPicture() {
        pipController?.startPictureInPicture()
    }
    
    public func stopPictureInPicture() {
        pipController?.stopPictureInPicture()
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate 实现
@available(iOS 15.0, tvOS 15.0, macOS 12.0, *)
extension PiPController: AVPictureInPictureSampleBufferPlaybackDelegate {
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        // 画中画播放/暂停切换
    }
    
    public func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        return CMTimeRange(start: .zero, duration: CMTime(seconds: 100, preferredTimescale: 600))
    }
    
    public func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        return false
    }
    
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        // 画中画尺寸变更
    }
    
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
