import Foundation

public final class InternalLogger {
    private let executor = LogExecutor()
    public let tag: String
    public let level: LogLevel
    private var appenders: [Appender] = []
    private var mergers: [ObjectIdentifier: LogMerger] = [:]
    private var closed = false
    public init(logGroup: String, level: LogLevel = .info) { tag = logGroup; self.level = level }
    public func addAppender(_ appender: Appender) {
        executor.sync {
            guard !closed, !appenders.contains(where: { $0 === appender }) else { return }
            appenders.append(appender)
            if let merger = appender.makeLogMerger() { mergers[ObjectIdentifier(appender)] = merger }
        }
    }
    public func removeAppender(_ appender: Appender) {
        executor.sync {
            mergers.removeValue(forKey: ObjectIdentifier(appender))?.destroy()
            appenders.removeAll { $0 === appender }
        }
    }
    public func log(_ level: LogLevel, messageType: MessageType = .log, messages: [Any]) {
        executor.sync {
            guard !closed, level.rawValue >= self.level.rawValue, !messages.isEmpty else { return }
            let message = messages.map { String(describing: $0) }.joined(separator: " ")
            for appender in appenders { appender.append(level: level, tag: tag, message: message, messageType: messageType) }
        }
    }
    /// Android statistic methods bypass the textual log-level filter.
    public func statistic(_ level: LogLevel, name: String, data: Double) {
        executor.sync {
            guard !closed, data.isFinite else { return }
            for appender in appenders { appender.appendStatLog(level: level, tag: tag, name: name, data: data) }
        }
    }
    public func merged(_ level: LogLevel, messageType: MessageType = .log, similarity: Int, format: String, args: [Any]) {
        executor.sync {
            guard !closed, level.rawValue >= self.level.rawValue else { return }
            for appender in appenders {
                if let merger = mergers[ObjectIdentifier(appender)] {
                    merger.pushLog(level: level, tag: tag, messageType: messageType, similarity: similarity, format: format, args: args)
                } else {
                    appender.append(level: level, tag: tag, message: LogMerger.formatBraces(format, args), messageType: messageType)
                }
            }
        }
    }
    public func onSourceChanged(srcUrl: String, srcType: String) {
        executor.sync {
            guard !closed else { return }
            for merger in mergers.values { merger.flush() }
            for appender in appenders { appender.onSourceChanged(srcUrl: srcUrl, srcType: srcType) }
        }
    }
    public func flushLog() {
        executor.sync {
            for merger in mergers.values { merger.flush() }
            for appender in appenders { appender.flush() }
        }
    }
    /// Appenders are externally owned and may be shared by other groups.
    public func destroy() {
        executor.sync {
            closed = true
            for merger in mergers.values { merger.destroy() }
            mergers.removeAll(); appenders.removeAll()
        }
    }
}

/// Configured by export.Init or explicitly by the host application.
public enum Logger {
    private static let executor = LogExecutor()
    private static var loggers: [String: InternalLogger] = [:]
    private static var external: [Appender] = []
    private static var owned: [Appender] = []
    private static var ownedByGroup: [String: [Appender]] = [:]
    private static var factory: ((String) -> [Appender])?
    private static var minimumLevel: LogLevel = .info
    private static var currentSource: (url: String, type: String)?

    /// Factory creates per-group appenders owned by Logger. Custom appenders are caller-owned.
    public static func configure(level: LogLevel = .info, appenderFactory: @escaping (String) -> [Appender]) {
        executor.sync {
            destroy()
            minimumLevel = level; factory = appenderFactory
        }
    }
    /// Explicit opt-in convenience wiring; does not fetch remote application configuration.
    public static func initialize(config: VPlayerConfig, initConfig: InitConfig, version: String = "",
                                  transport: LogHTTPTransport = URLSessionLogTransport()) throws {
        let context = LogContext(config: config, deviceInfo: initConfig.deviceInfo, customInfo: initConfig.customInfo, version: version)
        let enabled = initConfig.appenders
        let level = LogLevel(rawValue: min(4, max(0, config.logConfig.level))) ?? .info
        var policy = LogUploadPolicy()
        policy.uploadIntervalSeconds = Double(config.logConfig.uploadIntervalSeconds)
        policy.maxAttachedMessageCount = max(0, config.runtimeStateCollect.stateCountLimit)
        let app = config.appVZPlayerConfigJsonString.data(using: .utf8)
            .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
        policy.statLogIsAttachedToLog = app["statLogIsAttachedToLog"] as? Bool ?? false
        policy.statsMinUploadIntervalMs = app["statsMinUploadIntervalMs"] as? Double ?? 180000
        let uploader: ESUploader?
        if enabled.contains("ESAppender") {
            if app["forceUseNewESUploader"] as? Bool != false, let auth = initConfig.getAuthorizationCallback {
                uploader = try NewESUploader(env: config.env, topicId: config.topicId, userId: String(config.userId), streamId: config.streamId, clusterDomain: initConfig.clusterDomain, authorization: auth, transport: transport)
            } else { uploader = try OldESUploader(server: config.logServerConfig, env: config.env, transport: transport) }
        } else { uploader = nil }
        let file: FileAppender?
        if let path = initConfig.fileAppenderPath, !path.isEmpty {
            file = try FileAppender(fileURL: URL(fileURLWithPath: path))
        } else { file = nil }
        configure(level: level) { group in
            var result: [Appender] = []
            if enabled.contains("ConsoleAppender") { result.append(ConsoleAppender()) }
            if let file = file { result.append(file) }
            if let uploader = uploader { result.append(ESUploadAppender(context: context, logGroup: group, policy: policy, uploader: uploader)) }
            return result
        }
        for appender in initConfig.externalAppenders { addAppender(appender) }
    }
    public static func getLogger(_ group: String = "default") -> InternalLogger {
        executor.sync {
            if let logger = loggers[group] { return logger }
            let logger = InternalLogger(logGroup: group, level: minimumLevel)
            let groupAppenders = factory?(group) ?? []
            ownedByGroup[group] = groupAppenders
            for appender in groupAppenders {
                logger.addAppender(appender)
                if !owned.contains(where: { $0 === appender }) { owned.append(appender) }
            }
            for appender in external { logger.addAppender(appender) }
            if let source = currentSource { logger.onSourceChanged(srcUrl: source.url, srcType: source.type) }
            loggers[group] = logger
            return logger
        }
    }
    /// Releases only this group's owned outputs; shared/external appenders remain alive.
    public static func releaseLogger(_ group: String) {
        executor.sync {
            guard let logger = loggers.removeValue(forKey: group) else { return }
            logger.flushLog()
            logger.destroy()
            let candidates = ownedByGroup.removeValue(forKey: group) ?? []
            for appender in candidates {
                let shared = ownedByGroup.values.contains { $0.contains { $0 === appender } }
                if !shared, owned.contains(where: { $0 === appender }) {
                    owned.removeAll { $0 === appender }
                    appender.finish()
                }
            }
        }
    }
    public static func addAppender(_ appender: Appender) {
        executor.sync {
            guard !external.contains(where: { $0 === appender }) else { return }
            external.append(appender)
            for logger in loggers.values { logger.addAppender(appender) }
        }
    }
    public static func removeAppender(_ appender: Appender) {
        executor.sync {
            external.removeAll { $0 === appender }
            for logger in loggers.values { logger.removeAppender(appender) }
        }
    }
    public static func flushLog() { executor.sync { for logger in loggers.values { logger.flushLog() } } }
    public static func onSourceChanged(srcUrl: String, srcType: String) {
        executor.sync {
            currentSource = (srcUrl, srcType)
            for logger in loggers.values { logger.onSourceChanged(srcUrl: srcUrl, srcType: srcType) }
        }
    }
    public static func destroy() {
        executor.sync {
            for logger in loggers.values { logger.destroy() }
            for appender in owned { appender.destroy() }
            loggers.removeAll(); owned.removeAll(); ownedByGroup.removeAll(); external.removeAll(); factory = nil
            currentSource = nil
        }
    }
}

public extension InternalLogger {
    func logD(_ messages: Any...) { log(.debug, messageType: .log, messages: messages) }
    func logMD(_ similarity: Int, _ format: String, _ args: Any...) { merged(.debug, messageType: .log, similarity: similarity, format: format, args: args) }
    func logAD(_ messages: Any...) { log(.debug, messageType: .attachedLog, messages: messages) }
    func logMAD(_ similarity: Int, _ format: String, _ args: Any...) { merged(.debug, messageType: .attachedLog, similarity: similarity, format: format, args: args) }
    func logSD(_ name: String, _ data: Double) { statistic(.debug, name: name, data: data) }
    func logI(_ messages: Any...) { log(.info, messageType: .log, messages: messages) }
    func logMI(_ similarity: Int, _ format: String, _ args: Any...) { merged(.info, messageType: .log, similarity: similarity, format: format, args: args) }
    func logAI(_ messages: Any...) { log(.info, messageType: .attachedLog, messages: messages) }
    func logMAI(_ similarity: Int, _ format: String, _ args: Any...) { merged(.info, messageType: .attachedLog, similarity: similarity, format: format, args: args) }
    func logSI(_ name: String, _ data: Double) { statistic(.info, name: name, data: data) }
    func logW(_ messages: Any...) { log(.warn, messageType: .log, messages: messages) }
    func logMW(_ similarity: Int, _ format: String, _ args: Any...) { merged(.warn, messageType: .log, similarity: similarity, format: format, args: args) }
    func logAW(_ messages: Any...) { log(.warn, messageType: .attachedLog, messages: messages) }
    func logMAW(_ similarity: Int, _ format: String, _ args: Any...) { merged(.warn, messageType: .attachedLog, similarity: similarity, format: format, args: args) }
    func logSW(_ name: String, _ data: Double) { statistic(.warn, name: name, data: data) }
    func logE(_ messages: Any...) { log(.error, messageType: .log, messages: messages) }
    func logME(_ similarity: Int, _ format: String, _ args: Any...) { merged(.error, messageType: .log, similarity: similarity, format: format, args: args) }
    func logAE(_ messages: Any...) { log(.error, messageType: .attachedLog, messages: messages) }
    func logMAE(_ similarity: Int, _ format: String, _ args: Any...) { merged(.error, messageType: .attachedLog, similarity: similarity, format: format, args: args) }
    func logSE(_ name: String, _ data: Double) { statistic(.error, name: name, data: data) }
    func logF(_ messages: Any...) { log(.fatal, messageType: .log, messages: messages) }
    func logMF(_ similarity: Int, _ format: String, _ args: Any...) { merged(.fatal, messageType: .log, similarity: similarity, format: format, args: args) }
    func logAF(_ messages: Any...) { log(.fatal, messageType: .attachedLog, messages: messages) }
    func logMAF(_ similarity: Int, _ format: String, _ args: Any...) { merged(.fatal, messageType: .attachedLog, similarity: similarity, format: format, args: args) }
    func logSF(_ name: String, _ data: Double) { statistic(.fatal, name: name, data: data) }
}

public extension Logger {
    static func logD(_ messages: Any...) { getLogger().log(.debug, messageType: .log, messages: messages) }
    static func logMD(_ similarity: Int, _ format: String, _ args: Any...) { getLogger().merged(.debug, messageType: .log, similarity: similarity, format: format, args: args) }
    static func logAD(_ messages: Any...) { getLogger().log(.debug, messageType: .attachedLog, messages: messages) }
    static func logMAD(_ similarity: Int, _ format: String, _ args: Any...) { getLogger().merged(.debug, messageType: .attachedLog, similarity: similarity, format: format, args: args) }
    static func logSD(_ name: String, _ data: Double) { getLogger().statistic(.debug, name: name, data: data) }
    static func logI(_ messages: Any...) { getLogger().log(.info, messageType: .log, messages: messages) }
    static func logMI(_ similarity: Int, _ format: String, _ args: Any...) { getLogger().merged(.info, messageType: .log, similarity: similarity, format: format, args: args) }
    static func logAI(_ messages: Any...) { getLogger().log(.info, messageType: .attachedLog, messages: messages) }
    static func logMAI(_ similarity: Int, _ format: String, _ args: Any...) { getLogger().merged(.info, messageType: .attachedLog, similarity: similarity, format: format, args: args) }
    static func logSI(_ name: String, _ data: Double) { getLogger().statistic(.info, name: name, data: data) }
    static func logW(_ messages: Any...) { getLogger().log(.warn, messageType: .log, messages: messages) }
    static func logMW(_ similarity: Int, _ format: String, _ args: Any...) { getLogger().merged(.warn, messageType: .log, similarity: similarity, format: format, args: args) }
    static func logAW(_ messages: Any...) { getLogger().log(.warn, messageType: .attachedLog, messages: messages) }
    static func logMAW(_ similarity: Int, _ format: String, _ args: Any...) { getLogger().merged(.warn, messageType: .attachedLog, similarity: similarity, format: format, args: args) }
    static func logSW(_ name: String, _ data: Double) { getLogger().statistic(.warn, name: name, data: data) }
    static func logE(_ messages: Any...) { getLogger().log(.error, messageType: .log, messages: messages) }
    static func logME(_ similarity: Int, _ format: String, _ args: Any...) { getLogger().merged(.error, messageType: .log, similarity: similarity, format: format, args: args) }
    static func logAE(_ messages: Any...) { getLogger().log(.error, messageType: .attachedLog, messages: messages) }
    static func logMAE(_ similarity: Int, _ format: String, _ args: Any...) { getLogger().merged(.error, messageType: .attachedLog, similarity: similarity, format: format, args: args) }
    static func logSE(_ name: String, _ data: Double) { getLogger().statistic(.error, name: name, data: data) }
    static func logF(_ messages: Any...) { getLogger().log(.fatal, messageType: .log, messages: messages) }
    static func logMF(_ similarity: Int, _ format: String, _ args: Any...) { getLogger().merged(.fatal, messageType: .log, similarity: similarity, format: format, args: args) }
    static func logAF(_ messages: Any...) { getLogger().log(.fatal, messageType: .attachedLog, messages: messages) }
    static func logMAF(_ similarity: Int, _ format: String, _ args: Any...) { getLogger().merged(.fatal, messageType: .attachedLog, similarity: similarity, format: format, args: args) }
    static func logSF(_ name: String, _ data: Double) { getLogger().statistic(.fatal, name: name, data: data) }
}
