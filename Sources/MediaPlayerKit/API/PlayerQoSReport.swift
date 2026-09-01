import Foundation

/// 播放质量监控 (QoS / QoE) 结构化度量模型
@objc public final class PlayerQoSReport: NSObject {
    /// 播放会话唯一 ID
    @objc public let sessionID: String
    /// 媒体源 URL
    @objc public let mediaURL: URL
    /// 使用的播放内核
    @objc public let engineName: String
    
    // --- 耗时度量 (毫秒) ---
    /// DNS 解析耗时 (ms)
    @objc public var dnsDuration: Double = 0
    /// TCP 建连耗时 (ms)
    @objc public var tcpConnectDuration: Double = 0
    /// HTTP 响应首包到达耗时 (ms)
    @objc public var firstPacketDuration: Double = 0
    /// 首帧渲染总耗时 (First Frame Latency, ms)
    @objc public var firstFrameDuration: Double = 0
    
    // --- 播放稳定性度量 ---
    /// 总播放时长 (秒)
    @objc public var totalPlayDuration: Double = 0
    /// 卡顿总次数
    @objc public var stutterCount: Int = 0
    /// 卡顿总耗时 (秒)
    @objc public var totalStutterDuration: Double = 0
    /// 解码丢帧总数
    @objc public var droppedFrames: Int = 0
    
    // --- 视频元信息 ---
    @objc public var videoWidth: Int = 0
    @objc public var videoHeight: Int = 0
    @objc public var videoCodec: String = ""
    @objc public var audioCodec: String = ""
    @objc public var isHardwareAccelerated: Bool = true
    
    // --- 错误信息 (如有) ---
    @objc public var errorCode: Int = 0
    @objc public var errorMessage: String = ""

    public init(sessionID: String, mediaURL: URL, engineName: String) {
        self.sessionID = sessionID
        self.mediaURL = mediaURL
        self.engineName = engineName
        super.init()
    }

    /// 转换为可用于上报数据大盘的字典格式
    @objc public func toDictionary() -> [String: Any] {
        return [
            "session_id": sessionID,
            "media_url": mediaURL.absoluteString,
            "engine": engineName,
            "dns_duration_ms": dnsDuration,
            "tcp_duration_ms": tcpConnectDuration,
            "first_packet_duration_ms": firstPacketDuration,
            "first_frame_duration_ms": firstFrameDuration,
            "play_duration_sec": totalPlayDuration,
            "stutter_count": stutterCount,
            "stutter_duration_sec": totalStutterDuration,
            "dropped_frames": droppedFrames,
            "resolution": "\(videoWidth)x\(videoHeight)",
            "video_codec": videoCodec,
            "audio_codec": audioCodec,
            "hw_accel": isHardwareAccelerated,
            "error_code": errorCode,
            "error_message": errorMessage
        ]
    }
}
