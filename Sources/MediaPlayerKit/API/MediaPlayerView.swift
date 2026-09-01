import Foundation
#if canImport(UIKit)
import UIKit

/// 播放器承载视图 (可与 UI 控件完全解耦)
@objc public final class MediaPlayerView: UIView {
    private weak var currentEngineRenderView: UIView?
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .black
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.backgroundColor = .black
    }
    
    /// 将播放引擎的底层渲染视图挂载到当前视图
    public func attachRenderView(_ renderView: UIView) {
        if currentEngineRenderView === renderView { return }
        currentEngineRenderView?.removeFromSuperview()
        
        renderView.frame = self.bounds
        renderView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.addSubview(renderView)
        self.sendSubviewToBack(renderView)
        currentEngineRenderView = renderView
    }
    
    /// 卸载底层渲染视图
    public func detachRenderView() {
        currentEngineRenderView?.removeFromSuperview()
        currentEngineRenderView = nil
    }
}
#endif
