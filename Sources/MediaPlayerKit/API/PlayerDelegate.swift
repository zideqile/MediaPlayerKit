import Foundation

// 前向声明
@class MediaPlayerController;

/// 播放器统一事件与状态代理协议
@objc public protocol MediaPlayerDelegate: AnyObject {
    /// 播放状态发生变更
    func player(_ player: MediaPlayerController, stateDidChange state: PlayerState)
    
    /// 播放进度与时间更新 (建议 0.25s~0.5s 回调一次)
    func player(_ player: MediaPlayerController, currentTime: TimeInterval, totalDuration: TimeInterval)
    
    /// 首帧视频画面成功渲染到屏幕 (首帧秒开指标触发点)
    func playerDidRenderFirstFrame(_ player: MediaPlayerController)
    
    /// 播放发生异常或错误
    func player(_ player: MediaPlayerController, didOccurError error: NSError)
    
    /// 播放器缓冲进度更新 (已缓存时长)
    @objc optional func player(_ player: MediaPlayerController, bufferedDuration: TimeInterval)
    
    /// 视频自然播放结束
    @objc optional func playerDidPlayToEndTime(_ player: MediaPlayerController)
    
    /// QoS 质量度量报告生成完成 (用于业务方上报自身 APM 系统)
    @objc optional func player(_ player: MediaPlayerController, didGenerateQoSReport report: PlayerQoSReport)
}
