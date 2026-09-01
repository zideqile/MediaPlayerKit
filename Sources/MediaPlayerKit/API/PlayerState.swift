import Foundation

/// 播放器生命周期状态机枚举
@objc public enum PlayerState: Int, CustomStringConvertible {
    /// 空闲/初始状态
    case idle
    /// 正在准备资源（DNS解析、建立连接、探测格式）
    case preparing
    /// 准备就绪，首帧已加载，可立即播放
    case readyToPlay
    /// 正在正常播放
    case playing
    /// 用户主动暂停
    case paused
    /// 正在缓冲中（网络波动导致水位不足）
    case buffering
    /// 播放完成
    case completed
    /// 播放发生不可恢复的错误
    case error
    /// 播放器已停止并释放核心解码管线
    case stopped

    public var description: String {
        switch self {
        case .idle: return "idle"
        case .preparing: return "preparing"
        case .readyToPlay: return "readyToPlay"
        case .playing: return "playing"
        case .paused: return "paused"
        case .buffering: return "buffering"
        case .completed: return "completed"
        case .error: return "error"
        case .stopped: return "stopped"
        }
    }
}
