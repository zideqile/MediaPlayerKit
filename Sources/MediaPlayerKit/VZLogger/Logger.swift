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
            let message = location.prefix + messages.map { LogFormatter.formatArgument($0) }.joined(separator: " ")
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
            let formattedArgs = args.map { LogFormatter.formatArgument($0) }
            for appender in appenders {
                if let merger = mergers[ObjectIdentifier(appender)] {
                    merger.pushLog(level: level, tag: tag, messageType: messageType, similarity: similarity, format: locatedFormat, args: formattedArgs)
                } else {
                    appender.append(level: level, tag: tag, message: LogMerger.formatBraces(locatedFormat, formattedArgs), messageType: messageType)
                }
            }
        }
    }
    /// Flush mergers before replacing the sink so pending text retains its old identity.
    func replaceAppender(_ old: Appender, with replacement: Appender) {
        executor.sync {
            guard !closed else { return }
            removeAppender(old)
            old.finish()
            addAppender(replacement)
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
    private static var streamFactory: ((String, LogContext) throws -> ESUploadAppender?)?
    private static var baseContext: LogContext?
    private static var streamContexts: [String: LogContext] = [:]
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
        policy.printAttachedLogsOnUpload = enabled.contains("ConsoleAppender")
        policy.uploadIntervalSeconds = Double(config.logConfig.uploadIntervalSeconds)
        policy.maxAttachedMessageCount = max(0, config.runtimeStateCollect.stateCountLimit)
        let app = config.appVZPlayerConfigJsonString.data(using: .utf8)
            .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
        policy.statLogIsAttachedToLog = app["statLogIsAttachedToLog"] as? Bool ?? false
        policy.statsMinUploadIntervalMs = app["statsMinUploadIntervalMs"] as? Double ?? 180000
        // Capture routing settings by value; callers may reuse their configuration.
        let env = config.env
        let clusterDomain = initConfig.clusterDomain
        let authorization = initConfig.getAuthorizationCallback
        let useNewUploader = app["forceUseNewESUploader"] as? Bool != false && authorization != nil
        let oldUploader: ESUploader? = enabled.contains("ESAppender") && !useNewUploader
            ? try OldESUploader(server: config.logServerConfig, env: env, transport: transport) : nil
        let makeUploader: (LogContext) throws -> ESUploader? = { context in
            guard enabled.contains("ESAppender") else { return nil }
            if useNewUploader, let auth = authorization {
                return try NewESUploader(env: env, topicId: context.topicId, userId: String(context.userId), streamId: context.streamId, clusterDomain: clusterDomain, authorization: auth, transport: transport)
            }
            return oldUploader
        }
        let uploader = try makeUploader(context)
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
        executor.sync {
            baseContext = context
            if uploader != nil {
                streamFactory = { group, context in
                    guard let uploader = try makeUploader(context) else { return nil }
                    return ESUploadAppender(context: context, logGroup: group, policy: policy, uploader: uploader)
                }
            }
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
    /// Changes only this player's stream identity. Call after settling the old stream.
    /// Old sinks drain asynchronously with their original context and upload endpoint.
    static func configureStream(_ group: String, context requested: LogContext) {
        executor.sync {
            guard var context = baseContext else { return }
            context.topicId = requested.topicId
            context.streamId = requested.streamId
            context.playerConfig = requested.playerConfig
            let previous = streamContexts[group] ?? baseContext
            let logger = getLogger(group)
            guard previous?.topicId != context.topicId || previous?.streamId != context.streamId else { return }
            do {
                if let replacement = try streamFactory?(group, context),
                   let old = ownedByGroup[group]?.first(where: { $0 is ESUploadAppender }) {
                    logger.replaceAppender(old, with: replacement)
                    ownedByGroup[group]?.removeAll { $0 === old }
                    ownedByGroup[group]?.append(replacement)
                    owned.removeAll { $0 === old }
                    owned.append(replacement)
                }
                streamContexts[group] = context
            } catch {
                logger.logE("stream_log_context_failed", error.localizedDescription)
            }
        }
    }

    /// Releases only this group's owned outputs; shared/external appenders remain alive.
    public static func releaseLogger(_ group: String) {
        executor.sync {
            guard let logger = loggers.removeValue(forKey: group) else { return }
            logger.flushLog()
            logger.destroy()
            streamContexts.removeValue(forKey: group)
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
            streamFactory = nil; baseContext = nil; streamContexts.removeAll()
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
