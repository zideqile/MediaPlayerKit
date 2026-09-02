import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 播放器承载视图 (支持 iOS, macOS, tvOS, visionOS 全平台)
@objc public final class MediaPlayerView: PlatformView {
    private weak var currentEngineRenderView: PlatformView?
    
    #if canImport(UIKit)
    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .black
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.backgroundColor = .black
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        currentEngineRenderView?.frame = self.bounds
    }
    #elseif canImport(AppKit)
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.cgColor
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.cgColor
    }
    
    public override func layout() {
        super.layout()
        currentEngineRenderView?.frame = self.bounds
    }
    #endif
    
    /// 将播放引擎的底层渲染视图挂载到当前视图
    public func attachRenderView(_ renderView: PlatformView) {
        if currentEngineRenderView === renderView { return }
        currentEngineRenderView?.removeFromSuperview()
        
        #if canImport(UIKit)
        renderView.frame = self.bounds
        renderView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.addSubview(renderView)
        self.sendSubviewToBack(renderView)
        #elseif canImport(AppKit)
        renderView.frame = self.bounds
        renderView.autoresizingMask = [.width, .height]
        self.addSubview(renderView)
        #endif
        currentEngineRenderView = renderView
    }
    
    /// 卸载底层渲染视图
    public func detachRenderView() {
        currentEngineRenderView?.removeFromSuperview()
        currentEngineRenderView = nil
    }
}
