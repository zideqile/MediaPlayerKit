import Foundation
import AVKit
import AVFoundation

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
    
    #if canImport(UIKit)
    /// 针对 AVPlayerLayer 初始化画中画
    public func setup(with playerLayer: AVPlayerLayer) {
        guard isPictureInPictureSupported else { return }
        pipController = AVPictureInPictureController(playerLayer: playerLayer)
        pipController?.delegate = self
    }
    
    /// 针对 AVSampleBufferDisplayLayer (Metal/硬解分支) 初始化画中画
    @available(iOS 15.0, *)
    public func setup(with sampleBufferLayer: AVSampleBufferDisplayLayer) {
        guard isPictureInPictureSupported else { return }
        let contentSource = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: sampleBufferLayer, playbackDelegate: nil)
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
