import Foundation

public struct LogUploadPolicy {
    public var uploadIntervalSeconds: TimeInterval = 30
    public var maxAttachedMessageCount = 10
    public var maxBufferedMessages = 1000
    public var maxMessageBytes = 8192
    public var maxChunkBytes = 10000
    public var maxStatisticNames = 100
    /// nil preserves all samples until upload, as Android does. Optional memory cap.
    public var maxStatisticSamplesPerName: Int? = nil
    public var statsMinUploadIntervalMs: TimeInterval = 180000
    public var statLogIsAttachedToLog = false
    public init() {}
}

public final class ESUploadAppender: Appender {
    private let executor = LogExecutor()
    private let context: LogContext
    private let group: String
    private let policy: LogUploadPolicy
    private let uploadTask: StatisticsUploadTask
    private var timer: DispatchSourceTimer?
    private var messages: [(LogLevel, String)] = []
    private var attached: [String] = []
    private var statistics: [String: [Double]] = [:]
    private var statisticsStarted: Date?
    private var index = 0
    private var dropped = 0
    private var sourceURL = ""
    private var sourceType = ""
    private var closed = false
    var mergeDelayMs: Int { Int(min(3600, max(0.1, policy.uploadIntervalSeconds.isFinite ? policy.uploadIntervalSeconds : 30)) * 500) }
    public init(context: LogContext, logGroup: String = "default", policy: LogUploadPolicy = LogUploadPolicy(), uploader: ESUploader) {
        self.context = context; group = logGroup; self.policy = policy
        uploadTask = StatisticsUploadTask(uploader: uploader)
        let timer = DispatchSource.makeTimerSource(queue: executor.queue)
        let interval = policy.uploadIntervalSeconds.isFinite ? max(0.1, policy.uploadIntervalSeconds) : 30
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.flushIfNeeded() }
        self.timer = timer; timer.resume()
    }
    public func append(level: LogLevel, tag: String, message: String, messageType: MessageType) {
        executor.sync {
            guard !closed else { return }
            let text = String(decoding: message.utf8.prefix(max(1, policy.maxMessageBytes)), as: UTF8.self)
            let line = "\(logTime()) \(level.label) \(text)\n"
            if messageType == .attachedLog {
                attached.append(line)
                if attached.count > max(0, policy.maxAttachedMessageCount) { attached.removeFirst() }
            } else {
                if messages.count >= max(1, policy.maxBufferedMessages) { messages.removeFirst(); dropped += 1 }
                messages.append((level, line))
            }
        }
    }
    public func appendStatLog(level: LogLevel, tag: String, name: String, data: Double) {
        executor.sync {
            guard !closed, data.isFinite else { return }
            guard statistics[name] != nil || statistics.count < max(1, policy.maxStatisticNames) else { dropped += 1; return }
            if statisticsStarted == nil { statisticsStarted = Date() }
            statistics[name, default: []].append(data)
            if let limit = policy.maxStatisticSamplesPerName, var samples = statistics[name] {
                let excess = samples.count - max(1, limit)
                if excess > 0 {
                    samples.removeFirst(excess)
                    statistics[name] = samples
                    dropped += excess
                }
            }
        }
    }
    private func record(_ chunk: [(LogLevel, String)]) -> [String: Any] {
        var global: [String: Any] = ["userIdUuid": context.userIdUuid, "deviceInfo": context.deviceInfo,
                                     "customInfo": context.customInfo, "version": context.version]
        if index % 10 == 0 {
            global["optionInfo"] = ["timezone": TimeZone.current.secondsFromGMT() / 3600, "UA": "MediaPlayerKit",
                                    "vendor": "Apple", "platform": ProcessInfo.processInfo.operatingSystemVersionString,
                                    "feature": "native", "playerConfig": context.playerConfig] as [String: Any]
        }
        var fields: [String: Any] = ["userId": context.userId, "topicId": context.topicId, "streamId": context.streamId,
            "globalPlayerInfo": global, "innerDrop": dropped + uploadTask.innerDrop, "index": index,
            "time": Int64(Date().timeIntervalSince1970 * 1000), "logGroup": group == "default" ? "" : group,
            "logs": chunk.map { $0.1 }.joined(), "attachedLogs": attached.joined(),
            "logLevels": LogLevel.allCases.filter { level in chunk.contains { $0.0 == level } }.map { $0.label.uppercased() + "," }.joined(),
            "currentPlayerInfo": ["srcUrl": sourceURL, "srcType": sourceType, "srcDomain": URL(string: sourceURL)?.host ?? ""]]
        if !statistics.isEmpty { fields["statLogs"] = statistics }
        return fields
    }
    private func flushBuffered(force: Bool) {
        guard !closed else { return }
        if messages.isEmpty && !force {
            if policy.statLogIsAttachedToLog {
                // Android only trims to 30 when statistics wait for ordinary logs.
                for name in Array(statistics.keys) {
                    if let samples = statistics[name] {
                        statistics[name] = Array(samples.suffix(30))
                    }
                }
                return
            }
            if let started = statisticsStarted, Date().timeIntervalSince(started) * 1000 < policy.statsMinUploadIntervalMs { return }
        }
        while !messages.isEmpty || !statistics.isEmpty || (force && !attached.isEmpty) {
            var chunk: [(LogLevel, String)] = []
            var bytes = (try? JSONSerialization.data(withJSONObject: record([])).count) ?? 0
            while let next = messages.first {
                if !chunk.isEmpty && bytes + next.1.utf8.count > max(1, policy.maxChunkBytes) { break }
                chunk.append(messages.removeFirst()); bytes += next.1.utf8.count
            }
            uploadTask.upload(record(chunk)); index += 1
            attached.removeAll(); statistics.removeAll(); statisticsStarted = nil
        }
    }
    public func makeLogMerger() -> LogMerger? { LogMerger(delayMs: mergeDelayMs, appender: self) }
    // Shared by the timer and deterministic policy tests.
    func flushIfNeeded() { executor.sync { flushBuffered(force: false) } }
    public func flush() { executor.sync { flushBuffered(force: true) } }
    public func onSourceChanged(srcUrl: String, srcType: String) {
        executor.sync {
            // Preserve the old source on logs collected before the switch.
            flushBuffered(force: true); sourceURL = srcUrl; sourceType = srcType
        }
    }
    public func finish() {
        executor.sync {
            guard !closed else { return }
            timer?.cancel(); timer = nil
            flushBuffered(force: true)
            closed = true
            // Keep this appender alive until drained or the deadline expires.
            uploadTask.finish { [self] in destroy() }
        }
    }
    public func destroy() {
        executor.sync { closed = true; timer?.cancel(); timer = nil; messages.removeAll(); attached.removeAll(); statistics.removeAll(); uploadTask.stop() }
    }
    deinit { timer?.cancel(); uploadTask.stop() }
}
