import Foundation

/// Adjacent formatted messages merge within a fixed window, retaining the first message.
public final class LogMerger {
    private let executor = LogExecutor()
    private let appender: Appender
    private let delay: TimeInterval
    private var timer: DispatchSourceTimer?
    private var pending: (LogLevel, String, MessageType, Int, String, [Any], String, Int)?
    private var closed = false
    public init(delayMs: Int, appender: Appender) {
        delay = Double(max(1, delayMs)) / 1000
        self.appender = appender
    }
    public static func formatBraces(_ pattern: String, _ args: [Any]) -> String {
        var result = pattern
        var cursor = result.startIndex
        for arg in args {
            guard let range = result.range(of: "{}", range: cursor..<result.endIndex) else { break }
            let value = String(describing: arg)
            result.replaceSubrange(range, with: value)
            cursor = result.index(range.lowerBound, offsetBy: value.count)
        }
        return result
    }
    public static func similarity(_ lhs: [Any], _ rhs: [Any]) -> Int {
        guard lhs.count == rhs.count else { return 0 }
        return zip(lhs, rhs).map { a, b -> Int in
            if let a = a as? String, let b = b as? String {
                if a == b { return 100 }
                // Bound quadratic work for large diagnostic payloads.
                guard a.count <= 2048, b.count <= 2048 else { return 0 }
                let x = Array(a), y = Array(b)
                guard !x.isEmpty, !y.isEmpty else { return 0 }
                var row = Array(0...y.count)
                for (i, c) in x.enumerated() {
                    var next = [i + 1]
                    for (j, d) in y.enumerated() {
                        next.append(min(row[j + 1] + 1, next[j] + 1, row[j] + (c == d ? 0 : 1)))
                    }
                    row = next
                }
                return Int((1 - Double(row.last!) / Double(max(x.count, y.count))) * 100)
            }
            if let a = a as? NSNumber, let b = b as? NSNumber {
                let x = a.doubleValue, y = b.doubleValue
                guard x.isFinite, y.isFinite else { return 0 }
                if abs(x - y) < 0.000001 { return 100 }
                return max(0, Int((1 - abs(x - y) / max(abs(x), abs(y))) * 100))
            }
            return 0
        }.min() ?? 100
    }
    public func pushLog(level: LogLevel, tag: String, messageType: MessageType, similarity: Int, format: String, args: [Any]) {
        executor.sync {
            guard !closed else { return }
            let threshold = min(100, max(0, similarity))
            if let p = pending, p.0 == level, p.1 == tag, p.2 == messageType,
               p.3 == threshold, p.4 == format, Self.similarity(p.5, args) >= threshold {
                pending?.7 += 1
                return
            }
            flushPending()
            pending = (level, tag, messageType, threshold, format, args, Self.formatBraces(format, args), 1)
            let timer = DispatchSource.makeTimerSource(queue: executor.queue)
            timer.schedule(deadline: .now() + delay)
            timer.setEventHandler { [weak self] in self?.flushPending() }
            self.timer = timer
            timer.resume()
        }
    }
    private func flushPending() {
        timer?.cancel(); timer = nil
        guard let p = pending else { return }
        pending = nil
        appender.append(level: p.0, tag: p.1, message: p.6 + (p.7 > 1 ? " [x\(p.7)]" : ""), messageType: p.2)
    }
    public func flush() { executor.sync { flushPending() } }
    public func destroy() { executor.sync { closed = true; flushPending() } }
    deinit { timer?.cancel() }
}
