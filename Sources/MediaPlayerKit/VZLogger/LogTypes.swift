import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif

/// Source location passed explicitly through wrappers; no stack walking or path disclosure.
public struct LogLocation {
    public let fileID: String
    public let function: String
    public let line: UInt
    public let typeName: String
    /// Swift has no built-in enclosing-type literal. Supply typeName for multi-type files;
    /// otherwise the filename is used as a readable fallback.
    public init(fileID: String, function: String, line: UInt, typeName: String? = nil) {
        self.fileID = fileID; self.function = function; self.line = line
        self.typeName = typeName ?? URL(fileURLWithPath: fileID).deletingPathExtension().lastPathComponent
    }
    public var prefix: String {
        let method = function.prefix { $0 != "(" }
        return "[\(typeName).\(method):\(line)] "
    }
}

/// 格式化日志参数：当参数为 JSON 字符串、字典或数据时，以键值对形式输出。
public enum LogFormatter {
    /// Round only serialized samples, preserving full-precision accumulation.
    static func roundedSample(_ value: Double) -> Double {
        guard value.isFinite, value.rounded(.towardZero) != value,
              abs(value) <= Double.greatestFiniteMagnitude / 100 else { return value }
        let result = (value * 100).rounded() / 100
        return result == 0 ? 0 : result
    }
    /// Human-readable units only for runtime log text; metric samples remain numeric.
    static func formatRuntimeMetrics(_ fields: [String: Double]) -> String {
        let displayNames = ["drop": "drop_frames", "drop_packet": "drop_packets",
                            "fps": "display_fps", "frame_rate": "nominal_fps"]
        return fields.keys.sorted().compactMap { name in
            guard let value = fields[name] else { return nil }
            let text: String
            switch name {
            case "bandwidth", "bitrate", "observed_bitrate", "video_bitrate", "audio_bitrate":
                text = scaled(value, base: 1000, units: ["bps", "Kbps", "Mbps", "Gbps", "Tbps"])
            case "net_bytes", "read_bytes", "net_bytes_total", "read_bytes_total", "bytes_read", "network_bytes":
                text = scaled(value, base: 1024, units: ["B", "KiB", "MiB", "GiB", "TiB"])
            case "net_speed", "read_speed":
                text = scaled(value, base: 1024, units: ["B/s", "KiB/s", "MiB/s", "GiB/s", "TiB/s"])
            case "fps", "frame_rate", "nominal_frame_rate", "display_fps":
                text = formatValue(value) + "fps"
            default:
                text = formatValue(value)
            }
            return "\(displayNames[name] ?? name)=\(text)"
        }.joined(separator: " ")
    }

    /// Human-readable runtime state text with seconds units for time metrics.
    static func formatRuntimeState(_ fields: [String: Any]) -> String {
        let timeKeys: Set<String> = ["bufferedEnd", "duration", "totalPlayTime", "videoCurrentTime", "currentTime"]
        let sortedKeys = fields.keys.sorted()
        return sortedKeys.map { key in
            let val = fields[key]!
            if timeKeys.contains(key) {
                if let number = val as? NSNumber {
                    let d = number.doubleValue
                    if d.isFinite {
                        return "\(key): \(formatValue(val))s"
                    }
                } else if let d = val as? Double, d.isFinite {
                    return "\(key): \(formatValue(d))s"
                }
            }
            return "\(key): \(formatValue(val))"
        }.joined(separator: ", ")
    }

    private static func scaled(_ value: Double, base: Double, units: [String]) -> String {
        var amount = value
        var index = 0
        if amount.isFinite {
            while (abs(amount) >= base || roundedSample(abs(amount)) >= base) && index < units.count - 1 {
                amount /= base
                index += 1
            }
        }
        return formatValue(roundedSample(amount)) + units[index]
    }

    /// 将日志消息中的参数转换为易读的文本。若为 JSON 字典/字符串/数据，转为键值对形式。
    public static func formatArgument(_ item: Any) -> String {
        if let source = item as? PlayerSource {
            return source.toKeyValueString()
        }
        if let dict = item as? [String: Any] {
            return formatDictionary(dict)
        }
        if let dict = item as? NSDictionary, let swiftDict = dict as? [String: Any] {
            return formatDictionary(swiftDict)
        }
        if let data = item as? Data {
            if let obj = try? JSONSerialization.jsonObject(with: data, options: []),
               let dict = obj as? [String: Any] {
                return formatDictionary(dict)
            }
        }
        if let str = item as? String {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
                if let data = trimmed.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data, options: []),
                   let dict = obj as? [String: Any] {
                    return formatDictionary(dict)
                }
            } else if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if let data = trimmed.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data, options: []),
                   let arr = obj as? [Any] {
                    return "[" + arr.map { formatValue($0) }.joined(separator: ", ") + "]"
                }
            }
        }
        return formatValue(item)
    }

    /// 格式化单个值（递归支持字典、数组、布尔等）
    public static func formatValue(_ val: Any) -> String {
        if val is NSNull {
            return "null"
        }
        if let subDict = val as? [String: Any] {
            return "[\(formatDictionary(subDict))]"
        }
        if let arr = val as? [[String: Any]] {
            let formattedArr = arr.map { "[\(formatDictionary($0))]" }.joined(separator: ", ")
            return "[\(formattedArr)]"
        }
        if let arr = val as? [Any] {
            let formattedArr = arr.map { formatValue($0) }.joined(separator: ", ")
            return "[\(formattedArr)]"
        }
        #if canImport(CoreFoundation)
        if let number = val as? NSNumber, CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        #endif
        if let number = val as? NSNumber, String(describing: type(of: val)).contains("Boolean") {
            return number.boolValue ? "true" : "false"
        }
        if type(of: val) == Bool.self, let b = val as? Bool {
            return b ? "true" : "false"
        }
        if let number = val as? NSNumber {
            let kind = String(cString: number.objCType)
            if kind == "f" || kind == "d" {
                let value = number.doubleValue
                guard value.isFinite else { return number.stringValue }
                // Integral floating-point metrics should not acquire a ".00" suffix.
                if value.rounded(.towardZero) == value {
                    return String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"),
                                  value == 0 ? 0 : value)
                }
                // Avoid negative zero; never convert integer IDs through Double.
                return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"),
                              abs(value) < 0.005 ? 0 : value)
            }
            return number.stringValue
        }
        return "\(val)"
    }

    /// 将字典递归格式化为有序的键值对形式：key1: value1, key2: value2
    public static func formatDictionary(_ dict: [String: Any]) -> String {
        let sortedKeys = dict.keys.sorted()
        return sortedKeys.map { key in
            let val = dict[key]!
            return "\(key): \(formatValue(val))"
        }.joined(separator: ", ")
    }
}

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
    /// Flush pending output and release owned resources without blocking the caller.
    func finish()
    func onSourceChanged(srcUrl: String, srcType: String)
}
public extension Appender {
    func appendStatLog(level: LogLevel, tag: String, name: String, data: Double) {}
    func makeLogMerger() -> LogMerger? { nil }
    func flush() {}
    func destroy() {}
    func finish() { flush(); destroy() }
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
        guard messageType != .attachedLog else { return }
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

/// Thread-safe monotonic sequence counter for ES log upload records within a logging session.
public final class ESUploadIndexCounter {
    private let lock = NSLock()
    private var current: Int

    public init(initialValue: Int = 0) {
        current = initialValue
    }

    public func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let value = current
        current += 1
        return value
    }

    public func reset(to value: Int = 0) {
        lock.lock()
        defer { lock.unlock() }
        current = value
    }

    public var currentValue: Int {
        lock.lock()
        defer { lock.unlock() }
        return current
    }
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
    public var indexCounter: ESUploadIndexCounter

    public init(config: VPlayerConfig, deviceInfo: String = "", customInfo: String = "", version: String = "",
                indexCounter: ESUploadIndexCounter = ESUploadIndexCounter()) {
        userId = config.userId; topicId = config.topicId; streamId = config.streamId
        userIdUuid = config.userIdUuid; self.deviceInfo = deviceInfo
        self.customInfo = customInfo
        self.version = version.isEmpty ? SDKVersion.version : version
        playerConfig = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(config))) as? [String: Any] ?? [:]
        self.indexCounter = indexCounter
    }
}
