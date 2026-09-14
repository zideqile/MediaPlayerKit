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
    @objc public var dnsDuration: Double = .nan
    /// TCP 建连耗时 (ms)
    @objc public var tcpConnectDuration: Double = .nan
    /// HTTP 响应首包到达耗时 (ms)
    @objc public var firstPacketDuration: Double = .nan
    /// 首帧渲染总耗时 (First Frame Latency, ms)
    @objc public var firstFrameDuration: Double = .nan
    
    // --- 播放稳定性度量 ---
    /// 总播放时长 (秒)
    @objc public var totalPlayDuration: Double = 0
    /// 卡顿总次数
    @objc public var stutterCount: Int = 0
    /// 卡顿总耗时 (秒)
    @objc public var totalStutterDuration: Double = 0
    /// 解码丢帧总数
    @objc public var droppedFrames: Int = -1
    
    // --- 视频元信息 ---
    @objc public var videoWidth: Int = 0
    @objc public var videoHeight: Int = 0
    @objc public var videoCodec: String = ""
    @objc public var audioCodec: String = ""
    /// Requested/known acceleration state; omitted from serialization until explicitly supplied.
    @objc public var isHardwareAccelerated: Bool = true { didSet { hardwareAccelerationKnown = true } }
    private var hardwareAccelerationKnown = false
    
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
        func measured(_ value: Double) -> Any { value.isFinite && value >= 0 ? value as Any : NSNull() }
        return [
            "schemaVersion": 2,
            "session_id": sessionID,
            "media_url": mediaURL.absoluteString,
            "engine": engineName,
            "dns_ms": measured(dnsDuration),
            "tcp_ms": measured(tcpConnectDuration),
            "first_packet_ms": measured(firstPacketDuration),
            "first_frame_time": measured(firstFrameDuration),
            "play_sec": totalPlayDuration,
            "stutter_count": stutterCount,
            "stall_sec": totalStutterDuration,
            "dropped_frames": droppedFrames >= 0 ? droppedFrames as Any : NSNull(),
            "resolution": videoWidth > 0 && videoHeight > 0 ? "\(videoWidth)x\(videoHeight)" as Any : NSNull(),
            "video_codec": videoCodec,
            "audio_codec": audioCodec,
            "hw_accel": hardwareAccelerationKnown ? isHardwareAccelerated as Any : NSNull(),
            "error_code": errorCode,
            "error_message": errorMessage
        ]
    }
}
