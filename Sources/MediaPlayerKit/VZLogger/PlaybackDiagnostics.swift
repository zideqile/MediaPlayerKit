import Foundation

/// One diagnostics group per facade instance; no cross-player source attribution.
/// Calls follow MultiSourcePlayer's main-thread contract. Time uses a monotonic clock.
final class PlaybackDiagnostics {
    let group: String
    private let statistics: PlaybackStatisticsTracker
    private let requests = PlayerRequestStatistics()
    private var statisticsTimer: Timer?
    private var statisticsInterval: TimeInterval = 10
    var onStatistics: (([String: Any]) -> Void)?
    var currentStatistics: [String: Any] { statistics.latest }
    private var metricsProvider: (() -> PlayerRuntimeMetrics?)?
    private var metricsInterval: TimeInterval = 3

    func configureRequests(threshold: Double, isLive: Bool) {
        requests.threshold = threshold; requests.isLive = isLive
    }
    func setRequestScope(_ scope: String) { statistics.requestScope = scope }
    func request(_ event: PlayerRequestEvent) {
        guard !closed else { return }
        requests.record(event)
    }
    private func flushRequests() {
        for (name, fields) in requests.drain() { logger.logE(name, fields) }
    }

    func configureStatistics(interval: TimeInterval) {
        statisticsInterval = interval.isFinite ? max(0, interval) : 10
        restartStatisticsTimer()
    }
    private func restartStatisticsTimer() {
        statisticsTimer?.invalidate(); statisticsTimer = nil
        guard !closed, attemptStarted != nil, statisticsInterval > 0 else { return }
        let timer = Timer(timeInterval: max(0.1, statisticsInterval), repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.sampleMetrics(interval: self.metricsInterval) { self.metricsProvider?() }
            self.statistics.publish()
            self.flushRequests()
        }
        statisticsTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func created() { statistics.created() }
    func newSources() {
        flushRequests(); requests.clear()
        endBuffering()
        statistics.reset()
        playingSince = nil; totalPlayTime = 0; lastState = nil
        onWaitingCount = 0; onPlayingCount = 0; internalErrorCount = 0
        totalStallCount = 0; totalStallDurationMs = 0; totalDropCount = 0
        stateTimer?.invalidate(); stateTimer = nil; stateProvider = nil; metricsProvider = nil
        statisticsTimer?.invalidate(); statisticsTimer = nil; attemptStarted = nil
    }
    func manualSwitch() { statistics.cancelRecovery() }
    func endAttempt(reason: String) {
        flushRequests(); requests.clear()
        if let start = playingSince { totalPlayTime += max(0, clock() - start) }
        playingSince = nil
        endBuffering()
        statistics.endAttempt(reason: reason)
    }

    private let clock: () -> TimeInterval
    private var attemptStarted: TimeInterval?
    private var firstFrameRecorded = false
    private var bufferingStarted: TimeInterval?
    private var lastState: PlayerState?
    private var closed = false
    private var metricsSampler = RuntimeMetricsSampler()
    private var lastMetricsTime: TimeInterval?
    private var stateTimer: Timer?
    private var stateProvider: (() -> [String: Any]?)?
    private var lastEvent: [String: String] = [:]
    private var playingSince: TimeInterval?
    private var totalPlayTime: TimeInterval = 0
    private var currentEngineName: String = ""
    private var onWaitingCount = 0
    private var onPlayingCount = 0
    private var internalErrorCount = 0
    private var totalStallCount = 0
    private var totalStallDurationMs: Double = 0
    private var totalDropCount: Int64 = 0

    /// Main-run-loop sampling continues even when buffering stops time callbacks.
    func startStateCollection(interval: TimeInterval, metrics: (() -> PlayerRuntimeMetrics?)? = nil,
                              provider: @escaping () -> [String: Any]?) {
        metricsProvider = metrics; metricsInterval = interval
        stateTimer?.invalidate()
        stateProvider = provider
        collectState(event: "loadstart")
        guard interval.isFinite, interval > 0 else { return }
        let timer = Timer(timeInterval: max(0.1, interval), repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.collectState()
            self.sampleMetrics(interval: self.metricsInterval) { self.metricsProvider?() }
        }
        stateTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func collectState(event: String? = nil) {
        guard !closed, var fields = stateProvider?() else { return }
        if let event = event { lastEvent = ["name": event, "time": logTime()] }
        fields["lastEvent"] = lastEvent
        fields["totalPlayTime"] = totalPlayTime + (playingSince.map { max(0, clock() - $0) } ?? 0)
        guard JSONSerialization.isValidJSONObject(fields),
              let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        logger.logAI("runtime state:", text)
    }
    private var logger: InternalLogger { Logger.getLogger(group) }

    init(group: String = "player-" + UUID().uuidString, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.group = group; self.clock = clock
        self.statistics = PlaybackStatisticsTracker(clock: clock)
        self.statistics.emit = { [weak self] record in
            guard let self = self else { return }
            self.logStatistics(record)
            self.onStatistics?(record)
        }
    }
    private func logStatistics(_ snapshot: [String: Any]) {
        for entry in PlaybackStatisticsLog.records(from: snapshot) {
            logger.log(entry.level, messages: [entry.name, entry.fields])
        }
    }

    func command(_ name: String, fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String = "MultiSourcePlayer") {
        guard !closed else { return }
        collectState(event: name)
        logger.logI(name, fileID: fileID, function: function, line: line, typeName: typeName)
    }
    func inputError(_ message: String, function: String, line: UInt) {
        guard !closed else { return }
        logger.logE(message, function: function, line: line, typeName: "H5Player")
    }
    func sources(_ sources: [PlayerSource], fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String = "MultiSourcePlayer") {
        guard !closed else { return }
        for source in sources {
            let type = source.type.lowercased()
            let fullType = type == "hls" && source.videoCodec == PlayerSource.CODEC_H265 ? "hls_hevc" : type
            logger.logI("add playerSource:", source.toKeyValueString(), fileID: fileID, function: function, line: line, typeName: typeName)
            logger.logSI("source_" + fullType, 1)
        }
    }
    func begin(source: PlayerSource, engine: PlayerEngineType, fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String = "MultiSourcePlayer") {
        guard !closed else { return }
        flushRequests()
        requests.begin(source: source.url, type: source.type)
        statistics.requestScope = "engineAggregate"
        let engineStr = engineName(engine)
        currentEngineName = engineStr
        statistics.begin(sourceURL: source.url, sourceType: source.type, sourceIndex: source.sourceIndex, engine: engineStr)
        stateTimer?.invalidate(); stateTimer = nil; stateProvider = nil; lastEvent = [:]
        endBuffering()
        logger.onSourceChanged(srcUrl: source.url, srcType: source.type)
        playingSince = nil; totalPlayTime = 0
        attemptStarted = clock(); firstFrameRecorded = false; lastState = nil
        metricsSampler = RuntimeMetricsSampler(); lastMetricsTime = nil
        restartStatisticsTimer()
        let type = source.type.lowercased()
        let fullType = type == "hls" && source.videoCodec == PlayerSource.CODEC_H265 ? "hls_hevc" : type
        logger.logSI("current_source_" + fullType, 1)
        logger.logSI("player_type", Double(engine.rawValue))
        logger.logI("create player", "engine:", engineStr, "source:", source.toKeyValueString(), fileID: fileID, function: function, line: line, typeName: typeName)
    }
    func state(_ state: PlayerState, fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String = "MultiSourcePlayer") {
        guard !closed, state != lastState else { return }
        if let start = playingSince { totalPlayTime += max(0, clock() - start) }
        playingSince = state == .playing ? clock() : nil
        collectState(event: state.description)
        lastState = state
        statistics.state(state)
        if state == .paused || state == .stopped || state == .completed {
            metricsSampler = RuntimeMetricsSampler(); lastMetricsTime = nil
        }
        if state == .buffering {
            onWaitingCount += 1
            if bufferingStarted == nil { bufferingStarted = clock() }
        } else {
            if state == .playing { onPlayingCount += 1 }
            endBuffering()
        }
        logger.logI("playState is:", state.description, fileID: fileID, function: function, line: line, typeName: typeName)
    }
    func firstFrame(size: CGSize, fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String = "MultiSourcePlayer") {
        guard !closed, !firstFrameRecorded, let start = attemptStarted else { return }
        firstFrameRecorded = true
        statistics.firstFrame()
        let elapsed = max(0, (clock() - start) * 1000)
        logger.logSI("first_frame_time", elapsed)
        // Unknown dimensions do not prove that the source is audio-only.
        if size.width > 0 && size.height > 0 { logger.logSI("has_video", 1) }
        logger.logI("firstFrameTime:", elapsed, "width:", size.width, "height:", size.height, fileID: fileID, function: function, line: line, typeName: typeName)
    }
    func sampleMetrics(interval: TimeInterval, provider: () -> PlayerRuntimeMetrics?,
                       fileID: String = #fileID, function: String = #function,
                       line: UInt = #line, typeName: String = "MultiSourcePlayer") {
        guard !closed, interval.isFinite, interval > 0,
              lastState == .playing || lastState == .buffering else { return }
        let time = clock()
        if let last = lastMetricsTime, time - last < interval { return }
        lastMetricsTime = time
        guard let metrics = provider() else {
            metricsSampler = RuntimeMetricsSampler()
            return
        }
        let fields = metricsSampler.sample(metrics, at: time)
        var summary = fields
        for (name, value) in [("read_bytes_total", metrics.bytesRead), ("net_bytes_total", metrics.networkBytes),
                              ("drop_count", metrics.droppedVideoFrames),
                              ("drop_packet_count", metrics.droppedVideoPackets),
                              ("media_requests_total", metrics.mediaRequests)] {
            if let value = value, value >= 0 { summary[name] = Double(value) }
        }
        statistics.updateMetrics(summary)
        for (name, value) in fields { logger.logSI(name, value) }
        if let dropTotal = metrics.droppedVideoFrames, dropTotal >= 0 {
            totalDropCount = dropTotal
            logger.logSI("drop_count", Double(dropTotal))
        }
        if !fields.isEmpty {
            let message = LogFormatter.formatRuntimeMetrics(fields)
            logger.logAI("runtime metrics:", message, fileID: fileID, function: function, line: line, typeName: typeName)
        }
    }

    func failed(_ failure: PlaybackAttemptFailure, fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String = "MultiSourcePlayer") {
        guard !closed else { return }
        flushRequests()
        statistics.failed(error: failure.error, willRecover: failure.action != .stop)
        if let start = playingSince { totalPlayTime += max(0, clock() - start) }
        playingSince = nil; lastState = .error
        endBuffering()
        collectState(event: "error")
        let engine = engineName(failure.engine)
        internalErrorCount += 1
        logger.logSI("internal_error", Double(internalErrorCount))
        logger.logSI("player_" + engine + "_error_code", Double(failure.error.code))
        if let start = attemptStarted { logger.logSI("player_time", max(0, (clock() - start) * 1000)) }
        logger.logE("player error", "source:", failure.sourceURL, "engine:", engine,
                    "domain:", failure.error.domain, "code:", failure.error.code,
                    "category:", failure.category.rawValue, "message:", failure.error.localizedDescription, fileID: fileID, function: function, line: line, typeName: typeName)
        switch failure.action {
        case .nextEngine: logger.logW("retry with fallback engine", fileID: fileID, function: function, line: line, typeName: typeName)
        case .nextSource: logger.logW("switch to nextSource", fileID: fileID, function: function, line: line, typeName: typeName)
        case .stop: logger.logE("all candidates exhausted or recovery stopped", fileID: fileID, function: function, line: line, typeName: typeName)
        }
    }
    func terminal(_ error: NSError, fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String = "MultiSourcePlayer") {
        guard !closed else { return }
        flushRequests(); requests.clear()
        statistics.endAttempt(reason: "terminalError")
        statisticsTimer?.invalidate(); statisticsTimer = nil
        stateTimer?.invalidate(); stateTimer = nil
        metricsProvider = nil; stateProvider = nil
        endBuffering()
        let engine = currentEngineName.isEmpty ? "avplayer" : currentEngineName
        logger.logSI("close_normal", 0)
        logger.logSI("player_" + engine + "_close_normal", 0)
        logger.logSI("total_stall", totalStallDurationMs)
        logger.logSI("stall_count", Double(totalStallCount))
        logger.logSI("on_waiting", Double(onWaitingCount))
        logger.logSI("on_playing", Double(onPlayingCount))
        if totalDropCount > 0 { logger.logSI("drop_count", Double(totalDropCount)) }
        logger.logE("player is error", "code:", error.code, "message:", error.localizedDescription, fileID: fileID, function: function, line: line, typeName: typeName)
        logger.flushLog()
    }
    func finish(fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String = "MultiSourcePlayer") {
        guard !closed else { return }
        flushRequests(); requests.clear()
        statistics.finish(reason: "destroy")
        statisticsTimer?.invalidate(); statisticsTimer = nil; metricsProvider = nil
        endBuffering()
        let engine = currentEngineName.isEmpty ? "avplayer" : currentEngineName
        logger.logSI("close_normal", 1)
        logger.logSI("player_" + engine + "_close_normal", 1)
        logger.logSI("total_stall", totalStallDurationMs)
        logger.logSI("stall_count", Double(totalStallCount))
        logger.logSI("on_waiting", Double(onWaitingCount))
        logger.logSI("on_playing", Double(onPlayingCount))
        if totalDropCount > 0 { logger.logSI("drop_count", Double(totalDropCount)) }
        if let start = playingSince { totalPlayTime += max(0, clock() - start) }
        playingSince = nil
        logger.logSI("current_time", totalPlayTime * 1000)
        collectState(event: "destroy")
        stateTimer?.invalidate(); stateTimer = nil; stateProvider = nil
        logger.logI("destroy player", fileID: fileID, function: function, line: line, typeName: typeName)
        closed = true
        Logger.releaseLogger(group)
    }
    private func endBuffering() {
        guard let start = bufferingStarted else { return }
        bufferingStarted = nil
        let duration = max(0, (clock() - start) * 1000)
        totalStallCount += 1
        totalStallDurationMs += duration
        logger.logSI("stall_duration", duration)
        logger.logSI("stall_count", Double(totalStallCount))
    }
    private func engineName(_ engine: PlayerEngineType) -> String {
        switch engine {
        case .avPlayer: return "avplayer"
        case .mePlayer: return "ksmeplayer"
        case .auto: return "auto"
        }
    }
    deinit { finish(typeName: "PlaybackDiagnostics") }
}
