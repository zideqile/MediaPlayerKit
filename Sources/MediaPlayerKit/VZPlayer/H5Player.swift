import Foundation
import CoreGraphics
import CoreFoundation

/// 对标 Android vzplayer 的 H5Player 门面实现 (实现 IH5Player 协议，持有并驱动内部 IPlayer)
@objc(H5Player)
public final class H5Player: NSObject, IH5Player, IPlayer, PlayerEventListener {
    private let multiPlayer: MultiSourcePlayer
    private weak var h5EventListener: H5EventListener?
    private var timeUpdateTimer: Timer?
    private var isPlayingState: Bool = false
    private var hasEmittedEnded = false
    @objc public var failureHistory: [PlaybackAttemptFailure] {
        executeOnMainThreadSync { self.multiPlayer.failureHistory }
    }
    
    @objc public init(playerView: MediaPlayerView, config: VPlayerConfig = VPlayerConfig()) {
        self.multiPlayer = MultiSourcePlayer(playerView: playerView, config: config)
        super.init()
        self.multiPlayer.AddEventListener(self)
    }
    
    // MARK: - IH5Player: 事件监听器注册 (1:1 对标 Android SetOnH5EventListener)
    
    @objc public func SetOnH5EventListener(_ listener: H5EventListener?) {
        executeOnMainThread {
            self.h5EventListener = listener
        }
    }
    
    // MARK: - IH5Player: 基础播放控制 (对标 Android IH5Player.java)
    
    @objc public func play() {
        executeOnMainThread {
            self.multiPlayer.Play()
        }
    }
    
    @objc public func pause() {
        executeOnMainThread {
            self.multiPlayer.Pause()
            self.stopTimeUpdateTimer()
        }
    }
    
    @objc public func resume() {
        executeOnMainThread {
            self.multiPlayer.Resume()
        }
    }
    
    @objc public func destroy() {
        executeOnMainThread {
            self.stopTimeUpdateTimer()
            self.multiPlayer.Destroy()
            self.h5EventListener = nil
        }
    }
    
    @objc public func setSources(_ sources: [PlayerSource]) {
        executeOnMainThread {
            self.multiPlayer.setSources(sources)
        }
    }
    
    @objc public func setConfig(_ config: VPlayerConfig) {
        executeOnMainThread {
            self.multiPlayer.setConfig(config)
        }
    }
    
    @objc public func SendEvent(_ eventName: String, _ paramsJson: String) {
        executeOnMainThread {
            if eventName == "NEXT_SOURCE" {
                _ = self.multiPlayer.switchToNextSource()
            } else if eventName == "SWITCH_SOURCE" {
                if let dict = self.parseJSON(paramsJson),
                   let idx = dict["index"] as? Int ?? (dict["sourceIndex"] as? Int) {
                    if !self.multiPlayer.switchToSource(index: idx) {
                        self.multiPlayer.logH5Error("SWITCH_SOURCE: rejected index")
                    }
                } else {
                    self.multiPlayer.logH5Error("SWITCH_SOURCE: invalid parameters")
                }
            }
        }
    }
    
    @objc public func switchSource(index: Int) -> Bool {
        return executeOnMainThreadSync {
            return self.multiPlayer.switchToSource(index: index)
        }
    }
    
    // MARK: - IH5Player: H5 风格属性 Getters / Setters (JSON 格式，对标 Android @JavascriptInterface)
    
    @objc public func get_currentTime() -> String {
        return executeOnMainThreadSync {
            let pos = self.multiPlayer.GetCurrentTime()
            return self.toJSON(["currentTime": pos])
        }
    }
    
    @objc public func set_currentTime(_ currentTime: String) -> Bool {
        return executeOnMainThreadSync {
            guard let dict = self.parseJSON(currentTime),
                  let time = self.number(dict["currentTime"]), time >= 0, time < Double(Int64.max) else {
                self.multiPlayer.logH5Error("set_currentTime: invalid parameters")
                return false
            }
            self.multiPlayer.Seek(Int64(time))
            return true
        }
    }
    
    @objc public func get_duration() -> String {
        return executeOnMainThreadSync {
            let dur = self.multiPlayer.GetDuration()
            return self.toJSON(["duration": dur])
        }
    }
    
    @objc public func get_pause() -> String {
        return executeOnMainThreadSync {
            return self.toJSON(["pause": self.multiPlayer.IsPaused()])
        }
    }
    
    @objc public func get_volume() -> String {
        return executeOnMainThreadSync {
            let vol = Double(String(format: "%.2f", self.multiPlayer.GetVolume())) ?? Double(self.multiPlayer.GetVolume())
            return self.toJSON(["volume": vol])
        }
    }
    
    @objc public func set_volume(_ volume: String) -> Bool {
        return executeOnMainThreadSync {
            guard let dict = self.parseJSON(volume),
                  let vol = self.number(dict["volume"]), (0...1).contains(vol) else {
                self.multiPlayer.logH5Error("set_volume: invalid parameters")
                return false
            }
            self.multiPlayer.SetVolume(Float(vol))
            return true
        }
    }
    
    @objc public func get_muted() -> String {
        return executeOnMainThreadSync {
            return self.toJSON(["muted": self.multiPlayer.IsMuted()])
        }
    }
    
    @objc public func set_muted(_ parametersJson: String) -> Bool {
        return executeOnMainThreadSync {
            guard let dict = self.parseJSON(parametersJson),
                  let muted = self.boolean(dict["muted"]) else {
                self.multiPlayer.logH5Error("set_muted: invalid parameters")
                return false
            }
            self.multiPlayer.SetMuted(muted)
            return true
        }
    }
    
    @objc public func get_videoWidth() -> String {
        return executeOnMainThreadSync {
            return self.toJSON(["videoWidth": self.multiPlayer.GetWidth()])
        }
    }
    
    @objc public func get_videoHeight() -> String {
        return executeOnMainThreadSync {
            return self.toJSON(["videoHeight": self.multiPlayer.GetHeight()])
        }
    }
    
    @objc public func get_loop() -> String {
        return executeOnMainThreadSync {
            return self.toJSON(["loop": self.multiPlayer.IsLoop()])
        }
    }
    
    @objc public func set_loop(_ parametersJson: String) -> Bool {
        return executeOnMainThreadSync {
            guard let dict = self.parseJSON(parametersJson),
                  let loop = self.boolean(dict["loop"]) else {
                self.multiPlayer.logH5Error("set_loop: invalid parameters")
                return false
            }
            self.multiPlayer.SetLoop(loop)
            return true
        }
    }
    
    @objc public func get_speed() -> String {
        return executeOnMainThreadSync {
            let speed = Double(String(format: "%.2f", self.multiPlayer.GetSpeed())) ?? Double(self.multiPlayer.GetSpeed())
            return self.toJSON(["speed": speed])
        }
    }
    
    @objc public func set_speed(_ parametersJson: String) -> Bool {
        return executeOnMainThreadSync {
            guard let dict = self.parseJSON(parametersJson),
                  let speed = self.number(dict["speed"]), speed > 0, speed <= Double(Float.greatestFiniteMagnitude), Float(speed) > 0 else {
                self.multiPlayer.logH5Error("set_speed: invalid parameters")
                return false
            }
            self.multiPlayer.SetSpeed(Float(speed))
            return true
        }
    }
    
    @objc public func get_buffered() -> String {
        return executeOnMainThreadSync {
            let range = self.multiPlayer.GetBuffered()
            return self.toJSON([
                "length": range.length,
                "start": range.start,
                "end": range.end
            ])
        }
    }
    
    @objc public func get_currentsource() -> String {
        return executeOnMainThreadSync {
            guard let source = self.multiPlayer.getCurrentSource() else {
                return "{}"
            }
            return source.toJSONString()
        }
    }
    
    // MARK: - IPlayer: 原生强类型协议透传 (方便 Native 开发者直接使用)
    
    @objc public func AddEventListener(_ listener: PlayerEventListener?) {
        executeOnMainThread { self.multiPlayer.AddEventListener(listener) }
    }
    
    @objc public func RemoveEventListener(_ listener: PlayerEventListener?) {
        executeOnMainThread { self.multiPlayer.RemoveEventListener(listener) }
    }
    
    @objc public func Play(_ sources: [PlayerSource]) -> Bool {
        return executeOnMainThreadSync {
            return self.multiPlayer.Play(sources)
        }
    }
    
    @objc public func Play() { play() }
    @objc public func Pause() { pause() }
    @objc public func Resume() { resume() }
    @objc public func Destroy() { destroy() }
    
    @objc public func Seek(_ seconds: Int64) {
        executeOnMainThread {
            self.multiPlayer.Seek(seconds)
        }
    }
    
    @objc public func GetCurrentTime() -> Int64 {
        return executeOnMainThreadSync { self.multiPlayer.GetCurrentTime() }
    }
    
    @objc public func GetDuration() -> Int64 {
        return executeOnMainThreadSync { self.multiPlayer.GetDuration() }
    }
    
    @objc public func IsPaused() -> Bool {
        return executeOnMainThreadSync { self.multiPlayer.IsPaused() }
    }
    
    @objc public func GetVolume() -> Float {
        return executeOnMainThreadSync { self.multiPlayer.GetVolume() }
    }
    
    @objc public func SetVolume(_ volume: Float) {
        executeOnMainThread { self.multiPlayer.SetVolume(volume) }
    }
    
    @objc public func IsMuted() -> Bool {
        return executeOnMainThreadSync { self.multiPlayer.IsMuted() }
    }
    
    @objc public func SetMuted(_ isMuted: Bool) {
        executeOnMainThread { self.multiPlayer.SetMuted(isMuted) }
    }
    
    @objc public func GetWidth() -> Int {
        return executeOnMainThreadSync { self.multiPlayer.GetWidth() }
    }
    
    @objc public func GetHeight() -> Int {
        return executeOnMainThreadSync { self.multiPlayer.GetHeight() }
    }
    
    @objc public func IsLoop() -> Bool {
        return executeOnMainThreadSync { self.multiPlayer.IsLoop() }
    }
    
    @objc public func SetLoop(_ loop: Bool) {
        executeOnMainThread { self.multiPlayer.SetLoop(loop) }
    }
    
    @objc public func GetSpeed() -> Float {
        return executeOnMainThreadSync { self.multiPlayer.GetSpeed() }
    }
    
    @objc public func SetSpeed(_ speed: Float) {
        executeOnMainThread { self.multiPlayer.SetSpeed(speed) }
    }
    
    @objc public func GetBuffered() -> BufferRange {
        return executeOnMainThreadSync { self.multiPlayer.GetBuffered() }
    }
    
    @objc public func SendEvent(_ eventName: String, params: [String: Any]?) {
        executeOnMainThread {
            self.multiPlayer.SendEvent(eventName, params: params)
        }
    }
    
    @objc public func getCurrentSource() -> PlayerSource? {
        return executeOnMainThreadSync { self.multiPlayer.getCurrentSource() }
    }
    
    // MARK: - 内部定时器与事件心跳
    
    private func startTimeUpdateTimer() {
        guard timeUpdateTimer == nil else { return }
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlayingState, !self.multiPlayer.IsPaused() else { return }
            let pos = self.multiPlayer.GetCurrentTime()
            self.h5EventListener?.onTimeUpdate(pos)
        }
    }
    
    private func stopTimeUpdateTimer() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
    }
    
    // MARK: - PlayerEventListener (监听内部 IPlayer 状态并转换为 W3C H5 标准事件)
    
    public func onStateChanged(state: PlayerState) {
        executeOnMainThread {
            switch state {
            case .idle, .stopped:
                self.isPlayingState = false
                self.stopTimeUpdateTimer()
            case .preparing:
                self.hasEmittedEnded = false
                self.isPlayingState = false
                self.stopTimeUpdateTimer()
                self.notifyH5Event("play")
            case .readyToPlay:
                self.notifyH5Event("canplaythrough")
            case .playing:
                self.hasEmittedEnded = false
                if !self.isPlayingState {
                    self.isPlayingState = true
                    self.notifyH5Event("playing")
                }
                self.startTimeUpdateTimer()
            case .paused:
                self.isPlayingState = false
                self.notifyH5Event("pause")
                self.stopTimeUpdateTimer()
            case .buffering:
                self.isPlayingState = false
                self.stopTimeUpdateTimer()
                self.notifyH5Event("waiting")
            case .completed:
                self.emitEndedIfNeeded()
            case .error:
                self.isPlayingState = false
                self.stopTimeUpdateTimer()
            }
        }
    }
    
    public func onFirstFrameRendered() {
        // 首帧仅代表渲染完成；playing 统一由播放状态驱动，避免重复事件或暂停后误报。
    }
    
    public func onTimeUpdate(currentTime: Int64, totalDuration: Int64) {
        // 心跳由定时器统一驱动
    }
    
    public func onPlayAttemptFailed(_ failure: PlaybackAttemptFailure) {
        executeOnMainThread { self.h5EventListener?.onPlayAttemptFailed?(failure) }
    }

    public func onRecoveryStarted(_ failure: PlaybackAttemptFailure) {
        executeOnMainThread {
            self.isPlayingState = false
            self.stopTimeUpdateTimer()
            self.h5EventListener?.onRecoveryStarted?(failure)
            self.notifyH5Event("recovering")
        }
    }

    public func onError(code: Int, errMsg: String) {
        executeOnMainThread {
            self.isPlayingState = false
            self.stopTimeUpdateTimer()
            // Android H5Player maps the terminal native error to PlayerWARN.
            self.notifyH5Event("PlayerWARN")
        }
    }
    
    public func onPlayToEnd() {
        executeOnMainThread {
            self.emitEndedIfNeeded()
        }
    }
    
    public func onSourceSwitched(source: PlayerSource) {
        // 切换源时不提前伪造 playing 事件，待底层首帧/播放就绪由状态机通知
    }
    
    public func onWarnMessage(msg: String) {
        // Intermediate diagnostics remain available to native listeners.
        // H5 recovery is signalled by onRecoveryStarted, never by PlayerWARN.
    }
    
    private func emitEndedIfNeeded() {
        isPlayingState = false
        stopTimeUpdateTimer()
        guard !hasEmittedEnded else { return }
        hasEmittedEnded = true
        notifyH5Event("ended")
    }

    private func notifyH5Event(_ name: String) {
        h5EventListener?.onEvent(name)
    }
    
    // MARK: - 辅助工具
    
    private func executeOnMainThread(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
    
    private func executeOnMainThreadSync<T>(_ block: () -> T) -> T {
        if Thread.isMainThread {
            return block()
        } else {
            return DispatchQueue.main.sync(execute: block)
        }
    }
    
    private func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    private func boolean(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }
    private func parseJSON(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }
    
    private func toJSON(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}
