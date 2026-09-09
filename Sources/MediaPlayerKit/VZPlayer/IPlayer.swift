import Foundation

/// 强类型缓冲区间数据模型 (1:1 严格对标 Android vzplayer 的 BufferRange)
@objc(BufferRange)
public final class BufferRange: NSObject {
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

/// 内部 Native 播放器状态事件回调监听器 (1:1 严格对标 Android PlayerEventListener)
@objc public protocol PlayerEventListener: AnyObject {
    func onStateChanged(state: PlayerState)
    func onFirstFrameRendered()
    func onTimeUpdate(currentTime: Int64, totalDuration: Int64)
    /// One attempt failed; recovery may still follow. Optional for existing clients.
    @objc optional func onPlayAttemptFailed(_ failure: PlaybackAttemptFailure)
    @objc optional func onRecoveryStarted(_ failure: PlaybackAttemptFailure)
    /// Final failure only, after the recovery policy stops.
    func onError(code: Int, errMsg: String)
    func onPlayToEnd()
    func onSourceSwitched(source: PlayerSource)
    func onWarnMessage(msg: String)
}

/// Native 内部核心强类型播放器抽象协议 (1:1 严格对标 Android vzplayer 的 IPlayer.java)
@objc public protocol IPlayer: AnyObject {
    // MARK: - 事件监听器注册 (对齐 Android IPlayer)
    @objc func AddEventListener(_ listener: PlayerEventListener?)
    @objc func RemoveEventListener(_ listener: PlayerEventListener?)
    
    // MARK: - 基础播放生命周期控制 (1:1 对标 Android IPlayer.java)
    @objc func Play(_ sources: [PlayerSource]) -> Bool
    @objc func Play()
    @objc func Pause()
    @objc func Resume()
    @objc func Destroy()
    
    // MARK: - 进度控制与状态读取 (强类型秒数 Int64)
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
    @objc func GetBuffered() -> BufferRange
    
    // MARK: - 多源与事件派发 (1:1 对标 Android IPlayer.java)
    @objc func SendEvent(_ eventName: String, params: [String: Any]?)
    @objc func getCurrentSource() -> PlayerSource?
}
