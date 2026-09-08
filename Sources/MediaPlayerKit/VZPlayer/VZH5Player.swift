import Foundation
import CoreGraphics

/// 对标 Android vzplayer 的 H5Player 门面实现
@objc public final class VZH5Player: NSObject, IH5Player, VZMultiSourcePlayerDelegate {
    private let multiPlayer: VZMultiSourcePlayer
    private weak var eventListener: VZH5EventListener?
    private var timeUpdateTimer: Timer?
    private var isPlayingState: Bool = false
    
    @objc public init(playerView: MediaPlayerView, config: VZPlayerConfig = VZPlayerConfig()) {
        self.multiPlayer = VZMultiSourcePlayer(playerView: playerView, config: config)
        super.init()
        self.multiPlayer.delegate = self
    }
    
    @objc public func setOnH5EventListener(_ listener: VZH5EventListener?) {
        executeOnMainThread {
            self.eventListener = listener
        }
    }
    
    // MARK: - 基础播放控制
    
    @objc public func play() {
        executeOnMainThread {
            self.multiPlayer.play()
            self.startTimeUpdateTimer()
        }
    }
    
    @objc public func pause() {
        executeOnMainThread {
            self.multiPlayer.pause()
            self.stopTimeUpdateTimer()
        }
    }
    
    @objc public func resume() {
        executeOnMainThread {
            self.multiPlayer.resume()
            self.startTimeUpdateTimer()
        }
    }
    
    @objc public func destroy() {
        executeOnMainThread {
            self.stopTimeUpdateTimer()
            self.multiPlayer.destroy()
            self.eventListener = nil
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
    
    @objc public func sendEvent(_ eventName: String, paramsJson: String) {
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
    
    // MARK: - H5 风格属性 Getters / Setters (JSON 格式)
    
    @objc public func get_currentTime() -> String {
        return executeOnMainThreadSync {
            let pos = Int64(self.multiPlayer.currentTime)
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
            let dur = Int64(self.multiPlayer.duration)
            return self.toJSON(["duration": dur])
        }
    }
    
    @objc public func get_pause() -> String {
        return executeOnMainThreadSync {
            return self.toJSON(["pause": self.multiPlayer.isPaused])
        }
    }
    
    @objc public func get_volume() -> String {
        return executeOnMainThreadSync {
            let vol = Double(String(format: "%.2f", self.multiPlayer.getVolume())) ?? Double(self.multiPlayer.getVolume())
            return self.toJSON(["volume": vol])
        }
    }
    
    @objc public func set_volume(_ volumeJson: String) -> Bool {
        return executeOnMainThreadSync {
            guard let dict = self.parseJSON(volumeJson),
                  let vol = dict["volume"] as? Double ?? (dict["volume"] as? Float).map(Double.init) else {
                return false
            }
            self.multiPlayer.setVolume(Float(vol))
            return true
        }
    }
    
    @objc public func get_muted() -> String {
        return executeOnMainThreadSync {
            return self.toJSON(["muted": self.multiPlayer.isMuted()])
        }
    }
    
    @objc public func set_muted(_ parametersJson: String) -> Bool {
        return executeOnMainThreadSync {
            guard let dict = self.parseJSON(parametersJson),
                  let muted = dict["muted"] as? Bool else {
                return false
            }
            self.multiPlayer.setMuted(muted)
            return true
        }
    }
    
    @objc public func get_videoWidth() -> String {
        return executeOnMainThreadSync {
            let width = Int(self.multiPlayer.naturalSize.width)
            return self.toJSON(["videoWidth": width])
        }
    }
    
    @objc public func get_videoHeight() -> String {
        return executeOnMainThreadSync {
            let height = Int(self.multiPlayer.naturalSize.height)
            return self.toJSON(["videoHeight": height])
        }
    }
    
    @objc public func get_loop() -> String {
        return executeOnMainThreadSync {
            return self.toJSON(["loop": self.multiPlayer.isLoop()])
        }
    }
    
    @objc public func set_loop(_ parametersJson: String) -> Bool {
        return executeOnMainThreadSync {
            guard let dict = self.parseJSON(parametersJson),
                  let loop = dict["loop"] as? Bool else {
                return false
            }
            self.multiPlayer.setLoop(loop)
            return true
        }
    }
    
    @objc public func get_speed() -> String {
        return executeOnMainThreadSync {
            let speed = Double(String(format: "%.2f", self.multiPlayer.getSpeed())) ?? Double(self.multiPlayer.getSpeed())
            return self.toJSON(["speed": speed])
        }
    }
    
    @objc public func set_speed(_ parametersJson: String) -> Bool {
        return executeOnMainThreadSync {
            guard let dict = self.parseJSON(parametersJson),
                  let speed = dict["speed"] as? Double ?? (dict["speed"] as? Float).map(Double.init) else {
                return false
            }
            self.multiPlayer.setSpeed(Float(speed))
            return true
        }
    }
    
    @objc public func get_buffered() -> String {
        return executeOnMainThreadSync {
            let start = 0
            let buffered = Int(self.multiPlayer.bufferedDuration)
            return self.toJSON([
                "length": 1,
                "start": start,
                "end": buffered
            ])
        }
    }
    
    @objc public func get_currentsource() -> String {
        return executeOnMainThreadSync {
            guard let source = self.multiPlayer.currentSource else {
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
            let pos = Int64(self.multiPlayer.currentTime)
            self.eventListener?.onTimeUpdate(pos)
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
                self.eventListener?.onEvent("play")
            case .readyToPlay:
                self.eventListener?.onEvent("canplaythrough")
            case .playing:
                self.isPlayingState = true
                self.eventListener?.onEvent("canplaythrough")
                self.eventListener?.onEvent("playing")
            case .paused:
                self.isPlayingState = false
                self.eventListener?.onEvent("pause")
            case .buffering:
                self.eventListener?.onEvent("waiting")
            case .completed:
                self.isPlayingState = false
                self.eventListener?.onEvent("ended")
            case .error:
                self.isPlayingState = false
            }
        }
    }
    
    public func multiSourcePlayer(_ player: VZMultiSourcePlayer, didRenderFirstFrame: Void) {
        executeOnMainThread {
            self.eventListener?.onEvent("playing")
        }
    }
    
    public func multiSourcePlayer(_ player: VZMultiSourcePlayer, currentTime: TimeInterval, totalDuration: TimeInterval) {
        // 时间更新由 500ms 定时器驱动
    }
    
    public func multiSourcePlayer(_ player: VZMultiSourcePlayer, didOccurError error: NSError) {
        executeOnMainThread {
            self.eventListener?.onError(error.code, errMsg: error.localizedDescription)
        }
    }
    
    public func multiSourcePlayerDidPlayToEnd(_ player: VZMultiSourcePlayer) {
        // ended 事件统一在 stateDidChange(.completed) 中派发，避免双重重复派发
    }
    
    public func multiSourcePlayer(_ player: VZMultiSourcePlayer, didSwitchToSource source: VZPlayerSource) {
        executeOnMainThread {
            self.eventListener?.onEvent("PlayerWARN")
        }
    }
    
    public func multiSourcePlayer(_ player: VZMultiSourcePlayer, didWarnMessage msg: String) {
        executeOnMainThread {
            self.eventListener?.onEvent("PlayerWARN")
        }
    }
    
    // MARK: - JSON 辅助方法
    
    private func toJSON(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
    
    private func parseJSON(_ jsonStr: String) -> [String: Any]? {
        guard let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        return obj
    }
    
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
}
