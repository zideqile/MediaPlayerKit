import Foundation

/// 播放器底层内核类型选择
@objc public enum PlayerEngineType: Int {
    /// 自动选择（点播默认自研 KSMEPlayer，特殊场景或失败时平滑降级至 AVPlayer）
    case auto
    /// 强制使用基于 FFmpeg + VideoToolbox + Metal 的自研多媒体管线
    case mePlayer
    /// 强制使用 Apple 原生 AVPlayer 管线
    case avPlayer
}

/// 播放器配置模型
@objc public final class PlayerConfig: NSObject, NSCopying {
    /// 首选播放内核
    @objc public var preferredEngine: PlayerEngineType = .auto
    /// 准备完成后是否自动起播
    @objc public var autoPlay: Bool = true
    /// 是否循环播放
    @objc public var isLoop: Bool = false
    /// 是否启用 VideoToolbox 硬件解码（默认开启）
    @objc public var enableHardwareDecode: Bool = true
    /// 是否启用本地边下边播与预加载代理
    @objc public var enableLocalCache: Bool = true
    /// 最大缓存时长（秒）
    @objc public var maxBufferDuration: TimeInterval = 30.0
    /// 恢复起播的低水位缓冲时长（秒）
    @objc public var lowBufferWatermark: TimeInterval = 1.5
    /// 网络请求超时时间（秒）
    @objc public var timeoutSeconds: TimeInterval = 10.0
    /// 自定义 HTTP 头部信息
    @objc public var customHeaders: [String: String] = [:]

    @objc public static func defaultConfig() -> PlayerConfig {
        return PlayerConfig()
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        let copy = PlayerConfig()
        copy.preferredEngine = self.preferredEngine
        copy.autoPlay = self.autoPlay
        copy.isLoop = self.isLoop
        copy.enableHardwareDecode = self.enableHardwareDecode
        copy.enableLocalCache = self.enableLocalCache
        copy.maxBufferDuration = self.maxBufferDuration
        copy.lowBufferWatermark = self.lowBufferWatermark
        copy.timeoutSeconds = self.timeoutSeconds
        copy.customHeaders = self.customHeaders
        return copy
    }
}
