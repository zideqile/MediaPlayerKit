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
        DispatchQueue.main.async {
            self.eventListener = listener
        }
    }
    
    // MARK: - 基础播放控制
    
    @objc public func play() {
        DispatchQueue.main.async {
            self.multiPlayer.play()
            self.startTimeUpdateTimer()
        }
    }
    
    @objc public func pause() {
        DispatchQueue.main.async {
            self.multiPlayer.pause()
            self.stopTimeUpdateTimer()
            self.eventListener?.onEvent("pause")
        }
    }
    
    @objc public func resume() {
        DispatchQueue.main.async {
            self.multiPlayer.resume()
            self.startTimeUpdateTimer()
        }
    }
    
    @objc public func destroy() {
        DispatchQueue.main.async {
            self.stopTimeUpdateTimer()
            self.multiPlayer.destroy()
            self.eventListener = nil
        }
    }
    
    @objc public func setSources(_ sources: [VZPlayerSource]) {
        DispatchQueue.main.async {
            self.multiPlayer.setSources(sources)
        }
    }
    
    @objc public func setConfig(_ config: VZPlayerConfig) {
        DispatchQueue.main.async {
            self.multiPlayer.setConfig(config)
        }
    }
    
    @objc public func sendEvent(_ eventName: String, paramsJson: String) {
        DispatchQueue.main.async {
            if eventName == "NEXT_SOURCE" {
                _ = self.multiPlayer.switchToNextSource()
            }
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
            return self.toJSON(["volume": Double(self.multiPlayer.getVolume())])
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
            return self.toJSON(["speed": Double(self.multiPlayer.getSpeed())])
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
            let start = Int(self.multiPlayer.currentTime)
            let buffered = Int(self.multiPlayer.bufferedDuration)
            return self.toJSON([
                "length": 1,
                "start": start,
                "end": start + buffered
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
        DispatchQueue.main.async {
            switch state {
            case .idle:
                break
            case .preparing:
                self.eventListener?.onEvent("play")
            case .playing:
                self.isPlayingState = true
                self.eventListener?.onEvent("canplaythrough")
                self.eventListener?.onEvent("playing")
            case .paused:
                self.isPlayingState = false
                self.eventListener?.onEvent("pause")
            case .buffering:
                self.eventListener?.onEvent("waiting")
            case .error:
                self.isPlayingState = false
            }
        }
    }
    
    public func multiSourcePlayer(_ player: VZMultiSourcePlayer, didRenderFirstFrame: Void) {
        DispatchQueue.main.async {
            self.eventListener?.onEvent("playing")
        }
    }
    
    public func multiSourcePlayer(_ player: VZMultiSourcePlayer, currentTime: TimeInterval, totalDuration: TimeInterval) {
        // 时间更新由 500ms 定时器驱动
    }
    
    public func multiSourcePlayer(_ player: VZMultiSourcePlayer, didOccurError error: NSError) {
        DispatchQueue.main.async {
            self.eventListener?.onError(error.code, errMsg: error.localizedDescription)
        }
    }
    
    public func multiSourcePlayerDidPlayToEnd(_ player: VZMultiSourcePlayer) {
        DispatchQueue.main.async {
            self.eventListener?.onEvent("ended")
        }
    }
    
    public func multiSourcePlayer(_ player: VZMultiSourcePlayer, didSwitchToSource source: VZPlayerSource) {
        DispatchQueue.main.async {
            self.eventListener?.onEvent("PlayerWARN")
        }
    }
    
    public func multiSourcePlayer(_ player: VZMultiSourcePlayer, didWarnMessage msg: String) {
        DispatchQueue.main.async {
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
    
    private func executeOnMainThreadSync<T>(_ block: () -> T) -> T {
        if Thread.isMainThread {
            return block()
        } else {
            return DispatchQueue.main.sync(execute: block)
        }
    }
}
