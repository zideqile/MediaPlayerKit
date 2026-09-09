import Foundation

/// 缓冲区间数据模型 (1:1 对标 Android vzplayer 的 BufferRange)
@objc(VZBufferRange)
public final class VZBufferRange: NSObject {
    @objc public var length: Int = 1
    @objc public var start: Int = 0
    @objc public var end: Int = 0
    
    @objc public override init() {
        super.init()
    }
    
    @objc public init(length: Int = 1, start: Int = 0, end: Int = 0) {
        self.length = length
        self.start = start
        self.end = end
        super.init()
    }
    
    @objc public func toDictionary() -> [String: Any] {
        return [
            "length": length,
            "start": start,
            "end": end
        ]
    }
}

/// 兼容 Android 原生双端无缝类名 BufferRange
@objc(BufferRange)
public typealias BufferRange = VZBufferRange

/// H5 事件与错误回调监听器 (1:1 对标 Android vzplayer 的 IH5Player.H5EventListener / VZPlayerEventListener)
@objc public protocol VZH5EventListener: AnyObject {
    /// 标准状态事件通知 ("play", "playing", "pause", "ended", "waiting", "canplaythrough", "PlayerWARN")
    func onEvent(_ eventName: String)
    
    /// 播放严重错误通知
    func onError(_ code: Int, errMsg: String)
    
    /// 播放进度定时心跳 (单位: 秒)
    func onTimeUpdate(_ currentTime: Int64)
}

/// 统一播放器操作接口 (1:1 完全对标 Android vzplayer 的 IPlayer.java)
@objc public protocol IPlayer: AnyObject {
    // MARK: - 事件监听器注册 (对齐 Android IPlayer)
    @objc func AddEventListener(_ listener: VZH5EventListener?)
    @objc func RemoveEventListener(_ listener: VZH5EventListener?)
    @objc func SetOnH5EventListener(_ listener: VZH5EventListener?)
    
    // MARK: - 基础播放生命周期控制 (1:1 对标 Android IPlayer.java)
    @objc func Play(_ sources: [VZPlayerSource]) -> Bool
    @objc func Play()
    @objc func Pause()
    @objc func Resume()
    @objc func Destroy()
    
    // MARK: - 进度控制与状态读取 (1:1 对标 Android IPlayer.java)
    /// 跳转播放进度 (单位: 秒)
    @objc func Seek(_ seconds: Int64)
    
    /// 获取当前播放时间点 (单位: 秒)
    @objc func GetCurrentTime() -> Int64
    
    /// 获取媒体总时长 (单位: 秒, 直播返回 0)
    @objc func GetDuration() -> Int64
    
    /// 是否处于暂停状态
    @objc func IsPaused() -> Bool
    
    // MARK: - 音量与静音 (1:1 对标 Android IPlayer.java)
    @objc func GetVolume() -> Float
    @objc func SetVolume(_ volume: Float)
    @objc func IsMuted() -> Bool
    @objc func SetMuted(_ isMuted: Bool)
    
    // MARK: - 画面尺寸与循环 (1:1 对标 Android IPlayer.java)
    @objc func GetWidth() -> Int
    @objc func GetHeight() -> Int
    @objc func IsLoop() -> Bool
    @objc func SetLoop(_ loop: Bool)
    
    // MARK: - 播放倍速与缓冲水位 (1:1 对标 Android IPlayer.java)
    @objc func GetSpeed() -> Float
    @objc func SetSpeed(_ speed: Float)
    @objc func GetBuffered() -> VZBufferRange
    
    // MARK: - 多源调度与自定义事件 (1:1 对标 Android IPlayer.java)
    @objc func SendEvent(_ eventName: String, paramsJson: String)
    @objc func getCurrentSource() -> VZPlayerSource?
    @objc func setSources(_ sources: [VZPlayerSource])
    @objc func setConfig(_ config: VZPlayerConfig)
    @objc func switchSource(index: Int) -> Bool
    
    // MARK: - H5 桥接专用属性访问 (JSON 格式入参出参，对标 Android @JavascriptInterface)
    @objc func get_currentTime() -> String
    @objc func set_currentTime(_ currentTimeJson: String) -> Bool
    @objc func get_duration() -> String
    @objc func get_pause() -> String
    @objc func get_volume() -> String
    @objc func set_volume(_ volumeJson: String) -> Bool
    @objc func get_muted() -> String
    @objc func set_muted(_ parametersJson: String) -> Bool
    @objc func get_videoWidth() -> String
    @objc func get_videoHeight() -> String
    @objc func get_loop() -> String
    @objc func set_loop(_ parametersJson: String) -> Bool
    @objc func get_speed() -> String
    @objc func set_speed(_ parametersJson: String) -> Bool
    @objc func get_buffered() -> String
    @objc func get_currentsource() -> String
}

/// 兼容历史别名
public typealias IH5Player = IPlayer
