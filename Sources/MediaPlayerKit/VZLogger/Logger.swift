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
    public func log(_ level: LogLevel, messageType: MessageType = .log, messages: [Any], fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) {
        executor.sync {
            guard !closed, level.rawValue >= self.level.rawValue, !messages.isEmpty else { return }
            let location = LogLocation(fileID: fileID, function: function, line: line, typeName: typeName)
            let message = location.prefix + messages.map { String(describing: $0) }.joined(separator: " ")
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
    public func merged(_ level: LogLevel, messageType: MessageType = .log, similarity: Int, format: String, args: [Any], fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) {
        executor.sync {
            guard !closed, level.rawValue >= self.level.rawValue else { return }
            let locatedFormat = LogLocation(fileID: fileID, function: function, line: line, typeName: typeName).prefix + format
            for appender in appenders {
                if let merger = mergers[ObjectIdentifier(appender)] {
                    merger.pushLog(level: level, tag: tag, messageType: messageType, similarity: similarity, format: locatedFormat, args: args)
                } else {
                    appender.append(level: level, tag: tag, message: LogMerger.formatBraces(locatedFormat, args), messageType: messageType)
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
    public static func initialize(config: VPlayerConfig, initConfig: InitConfig, version: String = SDKVersion.version,
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
    func logD(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { log(.debug, messageType: .log, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logMD(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { merged(.debug, messageType: .log, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logAD(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { log(.debug, messageType: .attachedLog, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logMAD(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { merged(.debug, messageType: .attachedLog, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logSD(_ name: String, _ data: Double) { statistic(.debug, name: name, data: data) }
    func logI(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { log(.info, messageType: .log, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logMI(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { merged(.info, messageType: .log, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logAI(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { log(.info, messageType: .attachedLog, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logMAI(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { merged(.info, messageType: .attachedLog, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logSI(_ name: String, _ data: Double) { statistic(.info, name: name, data: data) }
    func logW(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { log(.warn, messageType: .log, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logMW(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { merged(.warn, messageType: .log, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logAW(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { log(.warn, messageType: .attachedLog, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logMAW(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { merged(.warn, messageType: .attachedLog, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logSW(_ name: String, _ data: Double) { statistic(.warn, name: name, data: data) }
    func logE(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { log(.error, messageType: .log, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logME(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { merged(.error, messageType: .log, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logAE(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { log(.error, messageType: .attachedLog, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logMAE(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { merged(.error, messageType: .attachedLog, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logSE(_ name: String, _ data: Double) { statistic(.error, name: name, data: data) }
    func logF(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { log(.fatal, messageType: .log, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logMF(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { merged(.fatal, messageType: .log, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logAF(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { log(.fatal, messageType: .attachedLog, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logMAF(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { merged(.fatal, messageType: .attachedLog, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    func logSF(_ name: String, _ data: Double) { statistic(.fatal, name: name, data: data) }
}

public extension Logger {
    static func logD(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().log(.debug, messageType: .log, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logMD(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().merged(.debug, messageType: .log, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logAD(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().log(.debug, messageType: .attachedLog, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logMAD(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().merged(.debug, messageType: .attachedLog, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logSD(_ name: String, _ data: Double) { getLogger().statistic(.debug, name: name, data: data) }
    static func logI(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().log(.info, messageType: .log, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logMI(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().merged(.info, messageType: .log, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logAI(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().log(.info, messageType: .attachedLog, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logMAI(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().merged(.info, messageType: .attachedLog, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logSI(_ name: String, _ data: Double) { getLogger().statistic(.info, name: name, data: data) }
    static func logW(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().log(.warn, messageType: .log, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logMW(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().merged(.warn, messageType: .log, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logAW(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().log(.warn, messageType: .attachedLog, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logMAW(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().merged(.warn, messageType: .attachedLog, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logSW(_ name: String, _ data: Double) { getLogger().statistic(.warn, name: name, data: data) }
    static func logE(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().log(.error, messageType: .log, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logME(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().merged(.error, messageType: .log, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logAE(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().log(.error, messageType: .attachedLog, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logMAE(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().merged(.error, messageType: .attachedLog, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logSE(_ name: String, _ data: Double) { getLogger().statistic(.error, name: name, data: data) }
    static func logF(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().log(.fatal, messageType: .log, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logMF(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().merged(.fatal, messageType: .log, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logAF(_ messages: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().log(.fatal, messageType: .attachedLog, messages: messages, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logMAF(_ similarity: Int, _ format: String, _ args: Any..., fileID: String = #fileID, function: String = #function, line: UInt = #line, typeName: String? = nil) { getLogger().merged(.fatal, messageType: .attachedLog, similarity: similarity, format: format, args: args, fileID: fileID, function: function, line: line, typeName: typeName) }
    static func logSF(_ name: String, _ data: Double) { getLogger().statistic(.fatal, name: name, data: data) }
}
