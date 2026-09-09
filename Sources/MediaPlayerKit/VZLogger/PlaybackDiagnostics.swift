import Foundation

/// One diagnostics group per facade instance; no cross-player source attribution.
/// Calls follow MultiSourcePlayer's main-thread contract. Time uses a monotonic clock.
final class PlaybackDiagnostics {
    let group: String
    private let clock: () -> TimeInterval
    private var attemptStarted: TimeInterval?
    private var firstFrameRecorded = false
    private var bufferingStarted: TimeInterval?
    private var lastState: PlayerState?
    private var closed = false
    private var logger: InternalLogger { Logger.getLogger(group) }

    init(group: String = "player-" + UUID().uuidString, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.group = group; self.clock = clock
    }
    func command(_ name: String) {
        guard !closed else { return }
        logger.logI(name)
    }
    func sources(_ sources: [PlayerSource]) {
        guard !closed else { return }
        for source in sources {
            let type = source.type.lowercased()
            let fullType = type == "hls" && source.videoCodec == PlayerSource.CODEC_H265 ? "hls_hevc" : type
            logger.logI("add playerSource:", source.toJSONString())
            logger.logSI("source_" + fullType, 1)
        }
    }
    func begin(source: PlayerSource, engine: PlayerEngineType) {
        guard !closed else { return }
        endBuffering()
        logger.onSourceChanged(srcUrl: source.url, srcType: source.type)
        attemptStarted = clock(); firstFrameRecorded = false; lastState = nil
        logger.logI("create player", "engine:", engineName(engine), "source:", source.toJSONString())
    }
    func state(_ state: PlayerState) {
        guard !closed, state != lastState else { return }
        lastState = state
        if state == .buffering {
            if bufferingStarted == nil { bufferingStarted = clock() }
        } else { endBuffering() }
        logger.logI("playState is:", state.description)
    }
    func firstFrame(size: CGSize) {
        guard !closed, !firstFrameRecorded, let start = attemptStarted else { return }
        firstFrameRecorded = true
        let elapsed = max(0, (clock() - start) * 1000)
        logger.logSI("first_frame_time", elapsed)
        // Unknown dimensions do not prove that the source is audio-only.
        if size.width > 0 && size.height > 0 { logger.logSI("has_video", 1) }
        logger.logI("firstFrameTime:", elapsed, "width:", size.width, "height:", size.height)
    }
    func failed(_ failure: PlaybackAttemptFailure) {
        guard !closed else { return }
        endBuffering()
        let engine = engineName(failure.engine)
        logger.logE("player error", "source:", failure.sourceURL, "engine:", engine,
                    "domain:", failure.error.domain, "code:", failure.error.code,
                    "category:", failure.category.rawValue, "message:", failure.error.localizedDescription)
        logger.logSI("ios_player_" + engine + "_error_code", Double(failure.error.code))
        if let start = attemptStarted { logger.logSI("player_time", max(0, (clock() - start) * 1000)) }
        switch failure.action {
        case .nextEngine: logger.logW("retry with fallback engine")
        case .nextSource: logger.logW("switch to nextSource")
        case .stop: logger.logE("all candidates exhausted or recovery stopped")
        }
    }
    func terminal(_ error: NSError) {
        guard !closed else { return }
        endBuffering()
        logger.logE("player is error", "code:", error.code, "message:", error.localizedDescription)
        logger.flushLog()
    }
    func finish() {
        guard !closed else { return }
        endBuffering()
        logger.logI("destroy player")
        closed = true
        Logger.releaseLogger(group)
    }
    private func endBuffering() {
        guard let start = bufferingStarted else { return }
        bufferingStarted = nil
        // Per-episode measurement, not Android's sliding-window stall_duration.
        logger.logSI("ios_stall_episode_ms", max(0, (clock() - start) * 1000))
    }
    private func engineName(_ engine: PlayerEngineType) -> String {
        switch engine {
        case .avPlayer: return "avplayer"
        case .mePlayer: return "ksmeplayer"
        case .auto: return "auto"
        }
    }
    deinit { finish() }
}
