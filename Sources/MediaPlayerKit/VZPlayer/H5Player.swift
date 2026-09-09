import Foundation
import CoreGraphics

/// 对标 Android vzplayer 的 H5Player 门面实现 (实现 IH5Player 协议，持有并驱动内部 IPlayer)
@objc(H5Player)
public final class H5Player: NSObject, IH5Player, IPlayer, PlayerEventListener {
    private let multiPlayer: MultiSourcePlayer
    private var h5EventListeners: [H5EventListener] = []
    private var timeUpdateTimer: Timer?
    private var isPlayingState: Bool = false
    
    @objc public init(playerView: MediaPlayerView, config: VPlayerConfig = VPlayerConfig()) {
        self.multiPlayer = MultiSourcePlayer(playerView: playerView, config: config)
        super.init()
        self.multiPlayer.AddEventListener(self)
    }
    
    // MARK: - IH5Player: 事件监听器注册 (1:1 对标 Android SetOnH5EventListener)
    
    @objc public func SetOnH5EventListener(_ listener: H5EventListener?) {
        executeOnMainThread {
            self.h5EventListeners.removeAll()
            if let l = listener {
                self.h5EventListeners.append(l)
            }
        }
    }
    
    // MARK: - IH5Player: 基础播放控制 (对标 Android IH5Player.java)
    
    @objc public func play() {
        executeOnMainThread {
            self.multiPlayer.Play()
            self.startTimeUpdateTimer()
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
            self.startTimeUpdateTimer()
        }
    }
    
    @objc public func destroy() {
        executeOnMainThread {
            self.stopTimeUpdateTimer()
            self.multiPlayer.Destroy()
            self.h5EventListeners.removeAll()
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
                    _ = self.multiPlayer.switchToSource(index: idx)
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
                  let time = dict["currentTime"] as? Double ?? (dict["currentTime"] as? Int).map(Double.init) else {
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
                  let vol = dict["volume"] as? Double ?? (dict["volume"] as? Float).map(Double.init) else {
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
                  let muted = dict["muted"] as? Bool else {
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
                  let loop = dict["loop"] as? Bool else {
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
                  let speed = dict["speed"] as? Double ?? (dict["speed"] as? Float).map(Double.init) else {
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
        multiPlayer.AddEventListener(listener)
    }
    
    @objc public func RemoveEventListener(_ listener: PlayerEventListener?) {
        multiPlayer.RemoveEventListener(listener)
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
        stopTimeUpdateTimer()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let pos = self.multiPlayer.GetCurrentTime()
            for listener in self.h5EventListeners {
                listener.onTimeUpdate(pos)
            }
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
                break
            case .preparing:
                self.notifyH5Event("play")
            case .readyToPlay:
                self.notifyH5Event("canplaythrough")
            case .playing:
                self.isPlayingState = true
                self.notifyH5Event("playing")
                self.startTimeUpdateTimer()
            case .paused:
                self.isPlayingState = false
                self.notifyH5Event("pause")
                self.stopTimeUpdateTimer()
            case .buffering:
                self.notifyH5Event("waiting")
            case .completed:
                self.isPlayingState = false
                self.notifyH5Event("ended")
                self.stopTimeUpdateTimer()
            case .failed:
                self.isPlayingState = false
                self.stopTimeUpdateTimer()
            }
        }
    }
    
    public func onFirstFrameRendered() {
        executeOnMainThread {
            self.notifyH5Event("playing")
        }
    }
    
    public func onTimeUpdate(currentTime: Int64, totalDuration: Int64) {
        // 心跳由定时器统一驱动
    }
    
    public func onError(code: Int, errMsg: String) {
        executeOnMainThread {
            for listener in self.h5EventListeners {
                listener.onError(code, errMsg: errMsg)
            }
        }
    }
    
    public func onPlayToEnd() {
        executeOnMainThread {
            self.notifyH5Event("ended")
        }
    }
    
    public func onSourceSwitched(source: PlayerSource) {
        executeOnMainThread {
            self.notifyH5Event("playing")
        }
    }
    
    public func onWarnMessage(msg: String) {
        executeOnMainThread {
            self.notifyH5Event("PlayerWARN")
        }
    }
    
    private func notifyH5Event(_ name: String) {
        for listener in self.h5EventListeners {
            listener.onEvent(name)
        }
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

/// 兼容别名
public typealias VZH5Player = H5Player
