import Foundation
import CoreGraphics

/// 对标 Android vzplayer 的 IPlayer 核心实现 (1:1 严格对齐)
@objc public final class VZH5Player: NSObject, IPlayer, VZMultiSourcePlayerDelegate {
    private let multiPlayer: VZMultiSourcePlayer
    private var eventListeners: [VZH5EventListener] = []
    private var timeUpdateTimer: Timer?
    private var isPlayingState: Bool = false
    
    @objc public init(playerView: MediaPlayerView, config: VZPlayerConfig = VZPlayerConfig()) {
        self.multiPlayer = VZMultiSourcePlayer(playerView: playerView, config: config)
        super.init()
        self.multiPlayer.delegate = self
    }
    
    // MARK: - 事件监听器注册 (1:1 对标 Android IPlayer)
    
    @objc public func AddEventListener(_ listener: VZH5EventListener?) {
        executeOnMainThread {
            guard let l = listener else { return }
            if !self.eventListeners.contains(where: { $0 === l }) {
                self.eventListeners.append(l)
            }
        }
    }
    
    @objc public func RemoveEventListener(_ listener: VZH5EventListener?) {
        executeOnMainThread {
            guard let l = listener else { return }
            self.eventListeners.removeAll(where: { $0 === l })
        }
    }
    
    @objc public func SetOnH5EventListener(_ listener: VZH5EventListener?) {
        executeOnMainThread {
            self.eventListeners.removeAll()
            if let l = listener {
                self.eventListeners.append(l)
            }
        }
    }
    
    // MARK: - 基础播放控制 (1:1 对标 Android IPlayer.java)
    
    @objc public func Play(_ sources: [VZPlayerSource]) -> Bool {
        return executeOnMainThreadSync {
            self.multiPlayer.setSources(sources)
            self.multiPlayer.play()
            self.startTimeUpdateTimer()
            return true
        }
    }
    
    @objc public func Play() {
        executeOnMainThread {
            self.multiPlayer.play()
            self.startTimeUpdateTimer()
        }
    }
    
    @objc public func Pause() {
        executeOnMainThread {
            self.multiPlayer.pause()
            self.stopTimeUpdateTimer()
        }
    }
    
    @objc public func Resume() {
        executeOnMainThread {
            self.multiPlayer.resume()
            self.startTimeUpdateTimer()
        }
    }
    
    @objc public func Destroy() {
        executeOnMainThread {
            self.stopTimeUpdateTimer()
            self.multiPlayer.destroy()
            self.eventListeners.removeAll()
        }
    }
    
    // MARK: - 进度控制与状态读取 (1:1 对标 Android IPlayer.java)
    
    @objc public func Seek(_ seconds: Int64) {
        executeOnMainThread {
            self.multiPlayer.seek(to: TimeInterval(seconds))
        }
    }
    
    @objc public func GetCurrentTime() -> Int64 {
        return executeOnMainThreadSync {
            return Int64(self.multiPlayer.currentTime)
        }
    }
    
    @objc public func GetDuration() -> Int64 {
        return executeOnMainThreadSync {
            return Int64(self.multiPlayer.duration)
        }
    }
    
    @objc public func IsPaused() -> Bool {
        return executeOnMainThreadSync {
            return self.multiPlayer.isPaused
        }
    }
    
    // MARK: - 音量与静音 (1:1 对标 Android IPlayer.java)
    
    @objc public func GetVolume() -> Float {
        return executeOnMainThreadSync {
            return self.multiPlayer.getVolume()
        }
    }
    
    @objc public func SetVolume(_ volume: Float) {
        executeOnMainThread {
            self.multiPlayer.setVolume(volume)
        }
    }
    
    @objc public func IsMuted() -> Bool {
        return executeOnMainThreadSync {
            return self.multiPlayer.isMuted()
        }
    }
    
    @objc public func SetMuted(_ isMuted: Bool) {
        executeOnMainThread {
            self.multiPlayer.setMuted(isMuted)
        }
    }
    
    // MARK: - 画面尺寸与循环 (1:1 对标 Android IPlayer.java)
    
    @objc public func GetWidth() -> Int {
        return executeOnMainThreadSync {
            return Int(self.multiPlayer.naturalSize.width)
        }
    }
    
    @objc public func GetHeight() -> Int {
        return executeOnMainThreadSync {
            return Int(self.multiPlayer.naturalSize.height)
        }
    }
    
    @objc public func IsLoop() -> Bool {
        return executeOnMainThreadSync {
            return self.multiPlayer.isLoop()
        }
    }
    
    @objc public func SetLoop(_ loop: Bool) {
        executeOnMainThread {
            self.multiPlayer.setLoop(loop)
        }
    }
    
    // MARK: - 播放倍速与缓冲水位 (1:1 对标 Android IPlayer.java)
    
    @objc public func GetSpeed() -> Float {
        return executeOnMainThreadSync {
            return self.multiPlayer.getSpeed()
        }
    }
    
    @objc public func SetSpeed(_ speed: Float) {
        executeOnMainThread {
            self.multiPlayer.setSpeed(speed)
        }
    }
    
    @objc public func GetBuffered() -> VZBufferRange {
        return executeOnMainThreadSync {
            let start = Int(self.multiPlayer.currentTime)
            let end = start + Int(self.multiPlayer.bufferedDuration)
            return VZBufferRange(length: 1, start: start, end: end)
        }
    }
    
    // MARK: - 多源调度与自定义事件 (1:1 对标 Android IPlayer.java)
    
    @objc public func SendEvent(_ eventName: String, paramsJson: String) {
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
    
    @objc public func getCurrentSource() -> VZPlayerSource? {
        return executeOnMainThreadSync {
            return self.multiPlayer.currentSource
        }
    }
    
    @objc public func setSources(_ sources: [VZPlayerSource]) {
        executeOnMainThread {
            self.multiPlayer.setSources(sources)
        }
    }
    
    @objc public func setConfig(_ config: VZPlayerConfig) {
        executeOnMainThread {
            self.multiPlayer.setConfig(config)
        }
    }
    
    @objc public func switchSource(index: Int) -> Bool {
        return executeOnMainThreadSync {
            return self.multiPlayer.switchToSource(index: index)
        }
    }
    
    // MARK: - H5 风格属性 Getters / Setters (JSON 格式，对标 Android @JavascriptInterface)
    
    @objc public func get_currentTime() -> String {
        return executeOnMainThreadSync {
            let pos = self.GetCurrentTime()
            return self.toJSON(["currentTime": pos])
        }
    }
    
    @objc public func set_currentTime(_ currentTimeJson: String) -> Bool {
        return executeOnMainThreadSync {
            guard let dict = self.parseJSON(currentTimeJson),
                  let time = dict["currentTime"] as? Double ?? (dict["currentTime"] as? Int).map(Double.init) else {
                return false
            }
            self.multiPlayer.seek(to: time)
            return true
        }
    }
    
    @objc public func get_duration() -> String {
        return executeOnMainThreadSync {
            let dur = self.GetDuration()
            return self.toJSON(["duration": dur])
        }
    }
    
    @objc public func get_pause() -> String {
        return executeOnMainThreadSync {
            return self.toJSON(["pause": self.IsPaused()])
        }
    }
    
    @objc public func get_volume() -> String {
        return executeOnMainThreadSync {
            let vol = Double(String(format: "%.2f", self.GetVolume())) ?? Double(self.GetVolume())
            return self.toJSON(["volume": vol])
        }
    }
    
    @objc public func set_volume(_ volumeJson: String) -> Bool {
        return executeOnMainThreadSync {
            guard let dict = self.parseJSON(volumeJson),
                  let vol = dict["volume"] as? Double ?? (dict["volume"] as? Float).map(Double.init) else {
                return false
            }
            self.SetVolume(Float(vol))
            return true
        }
    }
    
    @objc public func get_muted() -> String {
        return executeOnMainThreadSync {
            return self.toJSON(["muted": self.IsMuted()])
        }
    }
    
    @objc public func set_muted(_ parametersJson: String) -> Bool {
        return executeOnMainThreadSync {
            guard let dict = self.parseJSON(parametersJson),
                  let muted = dict["muted"] as? Bool else {
                return false
            }
            self.SetMuted(muted)
            return true
        }
    }
    
    @objc public func get_videoWidth() -> String {
        return executeOnMainThreadSync {
            return self.toJSON(["videoWidth": self.GetWidth()])
        }
    }
    
    @objc public func get_videoHeight() -> String {
        return executeOnMainThreadSync {
            return self.toJSON(["videoHeight": self.GetHeight()])
        }
    }
    
    @objc public func get_loop() -> String {
        return executeOnMainThreadSync {
            return self.toJSON(["loop": self.IsLoop()])
        }
    }
    
    @objc public func set_loop(_ parametersJson: String) -> Bool {
        return executeOnMainThreadSync {
            guard let dict = self.parseJSON(parametersJson),
                  let loop = dict["loop"] as? Bool else {
                return false
            }
            self.SetLoop(loop)
            return true
        }
    }
    
    @objc public func get_speed() -> String {
        return executeOnMainThreadSync {
            let speed = Double(String(format: "%.2f", self.GetSpeed())) ?? Double(self.GetSpeed())
            return self.toJSON(["speed": speed])
        }
    }
    
    @objc public func set_speed(_ parametersJson: String) -> Bool {
        return executeOnMainThreadSync {
            guard let dict = self.parseJSON(parametersJson),
                  let speed = dict["speed"] as? Double ?? (dict["speed"] as? Float).map(Double.init) else {
                return false
            }
            self.SetSpeed(Float(speed))
            return true
        }
    }
    
    @objc public func get_buffered() -> String {
        return executeOnMainThreadSync {
            let range = self.GetBuffered()
            return self.toJSON([
                "length": range.length,
                "start": range.start,
                "end": range.end
            ])
        }
    }
    
    @objc public func get_currentsource() -> String {
        return executeOnMainThreadSync {
            guard let source = self.getCurrentSource() else {
                return "{}"
            }
            return source.toJSONString()
        }
    }
    
    // MARK: - 内部定时器与事件心跳
    
    private func startTimeUpdateTimer() {
        stopTimeUpdateTimer()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let pos = self.GetCurrentTime()
            for listener in self.eventListeners {
                listener.onTimeUpdate(pos)
            }
        }
    }
    
    private func stopTimeUpdateTimer() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
    }
    
    // MARK: - VZMultiSourcePlayerDelegate 代理回调
    
    public func multiSourcePlayer(_ player: VZMultiSourcePlayer, stateDidChange state: PlayerState) {
        executeOnMainThread {
            switch state {
            case .idle, .stopped:
                break
            case .preparing:
                self.notifyEvent("play")
            case .readyToPlay:
                self.notifyEvent("canplaythrough")
            case .playing:
                self.isPlayingState = true
                self.notifyEvent("playing")
                self.startTimeUpdateTimer()
            case .paused:
                self.isPlayingState = false
                self.notifyEvent("pause")
                self.stopTimeUpdateTimer()
            case .buffering:
                self.notifyEvent("waiting")
            case .completed:
                self.isPlayingState = false
                self.notifyEvent("ended")
                self.stopTimeUpdateTimer()
            case .failed:
                self.isPlayingState = false
                self.stopTimeUpdateTimer()
            }
        }
    }
    
    public func multiSourcePlayer(_ player: VZMultiSourcePlayer, didRenderFirstFrame: Void) {
        executeOnMainThread {
            self.notifyEvent("playing")
        }
    }
    
    public func multiSourcePlayer(_ player: VZMultiSourcePlayer, currentTime: TimeInterval, totalDuration: TimeInterval) {
        // 心跳由定时器统一驱动
    }
    
    public func multiSourcePlayer(_ player: VZMultiSourcePlayer, didOccurError error: NSError) {
        executeOnMainThread {
            for listener in self.eventListeners {
                listener.onError(error.code, errMsg: error.localizedDescription)
            }
        }
    }
    
    public func multiSourcePlayerDidPlayToEnd(_ player: VZMultiSourcePlayer) {
        executeOnMainThread {
            self.notifyEvent("ended")
        }
    }
    
    public func multiSourcePlayer(_ player: VZMultiSourcePlayer, didSwitchToSource source: VZPlayerSource) {
        executeOnMainThread {
            self.notifyEvent("playing")
        }
    }
    
    public func multiSourcePlayer(_ player: VZMultiSourcePlayer, didWarnMessage msg: String) {
        executeOnMainThread {
            self.notifyEvent("PlayerWARN")
        }
    }
    
    private func notifyEvent(_ name: String) {
        for listener in self.eventListeners {
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
