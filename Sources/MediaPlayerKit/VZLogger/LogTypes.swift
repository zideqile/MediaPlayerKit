import Foundation

public enum LogLevel: Int, Codable, CaseIterable {
    case debug = 0, info, warn, error, fatal
    public var label: String { ["debug", "info", "warn", "error", "fatal"][rawValue] }
}
public enum MessageType { case log, attachedLog, statLog }

/// Appenders may be shared between groups; implementations must be thread safe.
/// Removing an appender does not destroy it. Its owner controls its lifetime.
public protocol Appender: AnyObject {
    func append(level: LogLevel, tag: String, message: String, messageType: MessageType)
    func appendStatLog(level: LogLevel, tag: String, name: String, data: Double)
    /// Return a fresh merger for each logger. The logger owns and destroys it.
    /// Equivalent to Android's getLogMerger capability without shared ownership.
    func makeLogMerger() -> LogMerger?
    func flush()
    func destroy()
    func onSourceChanged(srcUrl: String, srcType: String)
}
public extension Appender {
    func appendStatLog(level: LogLevel, tag: String, name: String, data: Double) {}
    func makeLogMerger() -> LogMerger? { nil }
    func flush() {}
    func destroy() {}
    func onSourceChanged(srcUrl: String, srcType: String) {}
}

/// Serializes operations; nested operations on the same executor do not deadlock.
final class LogExecutor {
    let queue = DispatchQueue(label: "MediaPlayerKit.Logging.\(UUID().uuidString)")
    private let key = DispatchSpecificKey<Bool>()
    init() { queue.setSpecific(key: key, value: true) }
    func sync<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: key) == true { return try body() }
        return try queue.sync(execute: body)
    }
}

private let logDateFormatterKey = "com.mediaplayerkit.logDateFormatter"
func logTime(_ date: Date = Date()) -> String {
    let formatter: DateFormatter
    if let cached = Thread.current.threadDictionary[logDateFormatterKey] as? DateFormatter {
        formatter = cached
    } else {
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        Thread.current.threadDictionary[logDateFormatterKey] = formatter
    }
    return formatter.string(from: date)
}

public final class ConsoleAppender: Appender {
    public init() {}
    public func append(level: LogLevel, tag: String, message: String, messageType: MessageType) {
        NSLog("[%@] [%@] %@", level.label, tag, message)
    }
}

public final class FileAppender: Appender {
    private let executor = LogExecutor()
    private var handle: FileHandle?
    private var failure: Error?
    public var lastError: Error? { executor.sync { failure } }
    /// Opening errors are reported to the caller instead of silently discarding logs.
    public init(fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        handle = try FileHandle(forWritingTo: fileURL)
        try handle?.seekToEnd()
    }
    public func append(level: LogLevel, tag: String, message: String, messageType: MessageType) {
        executor.sync {
            do { try handle?.write(contentsOf: Data("[\(logTime())] [\(level.label)] [\(tag)] \(message)\n".utf8)) }
            catch { failure = error }
        }
    }
    public func flush() { executor.sync { do { try handle?.synchronize() } catch { failure = error } } }
    public func destroy() {
        executor.sync {
            do {
                try handle?.synchronize()
                try handle?.close()
            } catch {
                failure = error
            }
            handle = nil
        }
    }
    deinit { try? handle?.close() }
}

/// Immutable snapshot: later mutation of VPlayerConfig cannot change an in-flight record.
public struct LogContext {
    public var userId: Int64
    public var topicId: String
    public var streamId: String
    public var userIdUuid: String
    public var deviceInfo: String
    public var customInfo: String
    public var version: String
    public var playerConfig: [String: Any]
    public init(config: VPlayerConfig, deviceInfo: String = "", customInfo: String = "", version: String = "") {
        userId = config.userId; topicId = config.topicId; streamId = config.streamId
        userIdUuid = config.userIdUuid; self.deviceInfo = deviceInfo
        self.customInfo = customInfo; self.version = version
        playerConfig = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(config))) as? [String: Any] ?? [:]
    }
}
