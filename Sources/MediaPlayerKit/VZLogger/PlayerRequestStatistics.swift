import Foundation

/// Main-thread, bounded request summaries. Only observed requests enter this collector.
final class PlayerRequestStatistics {
    var threshold: Double = 600
    var isLive = true
    private var context: [String: Any] = [:]
    private var slow: [[String: Any]] = []
    private var status: [[String: Any]] = []
    private var errors: [[String: Any]] = []
    private var repeated: [String: [Double]] = [:]
    private var counts: [String: Int] = [:]
    private var seen: [String: Double] = [:]
    private var order: [String] = []

    func begin(source: String, type: String) {
        clear()
        context = ["playerInstance": UUID().uuidString, "sourceUrl": source,
                   "sourceType": type, "sourceDomain": URL(string: source)?.host ?? ""]
    }

    func record(_ event: PlayerRequestEvent) {
        guard !context.isEmpty, !event.url.isEmpty, event.url.utf8.count <= 8192, !event.cached else { return }
        var item: [String: Any] = ["url": event.url, "kind": event.kind]
        if let end = event.endAt, end.isFinite { item["endAt"] = end }
        if let elapsed = event.elapsed, elapsed.isFinite, elapsed >= 0,
           elapsed > (threshold.isFinite && threshold > 0 ? threshold : 600) {
            var entry = item
            entry["elapsed"] = elapsed
            if let size = event.size, size >= 0 { entry["size"] = size }
            append(entry, to: &slow)
        }
        // 206 and 304 are valid HTTP range/cache responses on native players.
        if let code = event.status, (400...599).contains(code) {
            var entry = item; entry["status"] = code
            append(entry, to: &status)
        } else if let code = event.errorCode {
            var entry = item; entry["code"] = code; entry["domain"] = event.errorDomain
            append(entry, to: &errors)
        }
        // Error-log entries do not prove a new request was started.
        guard let start = event.startAt, start.isFinite else { return }
        if let first = seen[event.url] {
            if repeated[event.url] == nil {
                if repeated.count >= 100, let key = repeated.keys.sorted().first {
                    repeated.removeValue(forKey: key); counts.removeValue(forKey: key)
                }
                repeated[event.url] = first.isFinite ? [first] : []
                counts[event.url] = first.isFinite ? 1 : 0
            }
            seen[event.url] = .nan // First occurrence is reported only once.
            counts[event.url, default: 0] += 1
            var times = repeated[event.url] ?? []
            times.append(start)
            repeated[event.url] = Array(times.suffix(30))
        } else {
            seen[event.url] = start; order.append(event.url)
            let limit = isLive ? 10 : 100
            if order.count > limit { seen.removeValue(forKey: order.removeFirst()) }
        }
    }

    func drain() -> [(String, [String: Any])] {
        var records: [(String, [String: Any])] = []
        func emit(_ name: String, _ info: Any) {
            var fields = context; fields["requestInfo"] = info
            records.append(("PlayerSourceRequestStatistics." + name, fields))
        }
        if !slow.isEmpty { emit("logSlowRequests", slow) }
        if !status.isEmpty { emit("logUnexpectedStatusRequests", status) }
        if !errors.isEmpty { emit("logNetworkErrors", errors) }
        if !repeated.isEmpty {
            let info: [[Any]] = repeated.keys.sorted().map { url in
                let times = repeated[url] ?? []
                return [url, ["count": counts[url] ?? 0, "startAt": times]]
            }
            emit("logAbnormalRequests", info)
        }
        slow.removeAll(); status.removeAll(); errors.removeAll(); repeated.removeAll(); counts.removeAll()
        // Retain the seen marker for detection across upload windows.
        // Counts in repeated summaries describe this bounded observation window.
        return records
    }

    func clear() {
        slow.removeAll(); status.removeAll(); errors.removeAll(); repeated.removeAll(); counts.removeAll()
        seen.removeAll(); order.removeAll(); context.removeAll()
    }
    private func append(_ item: [String: Any], to values: inout [[String: Any]]) {
        values.append(item)
        if values.count > 5 { values.removeFirst() }
    }
}
