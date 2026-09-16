import Foundation

/// Web-style, purpose-specific log records. The public QoE snapshot remains unchanged.
struct PlaybackStatisticsLog {
    let name: String
    let level: LogLevel
    let fields: [String: Any]

    static func records(from snapshot: [String: Any]) -> [PlaybackStatisticsLog] {
        let reason = snapshot["reason"] as? String ?? ""
        let context = snapshot.filter { ["sourceIndex", "engine"].contains($0.key) }
        var result: [PlaybackStatisticsLog] = []
        let window = snapshot["window"] as? [String: Any] ?? [:]
        let count = (window["stalledCount"] as? NSNumber)?.intValue ?? 0
        let duration = (window["stalledTotalDuration"] as? NSNumber)?.doubleValue ?? 0
        if count > 0 || duration > 0 {
            var fields = context
            fields["stalledCount"] = count
            fields["stalledTotalDuration"] = "\(LogFormatter.formatValue(duration))ms"
            result.append(Self(name: "StalledSummaryInfoStatistics.summarize", level: .error, fields: fields))
        }
        if reason == "created" {
            var fields = context
            if let ms = (snapshot["create_ms"] as? NSNumber)?.doubleValue, ms.isFinite {
                fields["elapsed"] = "\(LogFormatter.formatValue(ms))ms"
            } else if let ms = snapshot["create_ms"] as? Double, ms.isFinite {
                fields["elapsed"] = "\(LogFormatter.formatValue(ms))ms"
            } else {
                fields["elapsed"] = NSNull()
            }
            fields["createOK"] = snapshot["createOK"]
            result.append(Self(name: "playerCreation", level: .info, fields: fields))
        }
        let keyReasons: Set<String> = [
            "paused", "stopped", "seek", "buffering", "recovered", "ended", "sourceEnded"
        ]
        let isKeyActionOrEvent = keyReasons.contains(reason)
        let isAttemptEnded = snapshot["attemptEnded"] as? Bool == true
        let isSessionEnded = reason.hasPrefix("sessionEnded:")
        let isLifetimeEnded = reason == "lifetimeEnded"

        if isAttemptEnded || isKeyActionOrEvent {
            if snapshot["attempt"] != nil {
                var attemptContext = context
                attemptContext["sourceUrl"] = snapshot["sourceUrl"]
                if let attemptId = snapshot["attemptId"] as? String, !attemptId.isEmpty {
                    attemptContext["attemptId"] = shortID(attemptId)
                }
                result.append(playtime(snapshot, scope: "attempt", reason: reason, context: attemptContext))
            }
            if snapshot["source"] != nil {
                var sourceContext: [String: Any] = [:]
                sourceContext["sourceUrl"] = snapshot["sourceUrl"]
                sourceContext["engines"] = snapshot["sourceEngines"] ?? (snapshot["engine"].map { [$0] } ?? [])
                if let idx = snapshot["sourceIndex"] as? Int { sourceContext["sourceIndex"] = idx }
                if let sourceId = snapshot["sourceId"] as? String, !sourceId.isEmpty { sourceContext["sourceId"] = shortID(sourceId) }
                result.append(playtime(snapshot, scope: "source", reason: reason, context: sourceContext))
            }
            if snapshot["session"] != nil {
                var sessionContext: [String: Any] = [:]
                if let sessionId = snapshot["sessionId"] as? String, !sessionId.isEmpty { sessionContext["sessionId"] = shortID(sessionId) }
                result.append(playtime(snapshot, scope: "session", reason: reason, context: sessionContext))
            }
        } else if isSessionEnded {
            result.append(playtime(snapshot, scope: "session", reason: reason, context: [:]))
        }

        if isLifetimeEnded {
            result.append(playtime(snapshot, scope: "lifetime", reason: reason, context: [:]))
        }
        return result
    }

    private static func shortID(_ id: String) -> String { String(id.prefix { $0 != "-" }) }

    private static func playtime(_ snapshot: [String: Any], scope: String, reason: String,
                                 context: [String: Any]) -> PlaybackStatisticsLog {
        let stats = snapshot[scope] as? [String: Any] ?? [:]
        var fields = context
        fields["scope"] = scope
        fields["reason"] = reason
        if let ms = (stats["play_ms"] as? Double) ?? (stats["play_ms"] as? NSNumber)?.doubleValue, ms.isFinite {
            fields["totalPlayTime"] = "\(LogFormatter.formatValue(ms / 1000))s"
        } else {
            fields["totalPlayTime"] = NSNull()
        }
        if scope == "session", let id = snapshot["sessionId"] as? String, !id.isEmpty {
            fields["sessionId"] = shortID(id)
        }
        if scope == "lifetime" { fields["attempts"] = stats["attempts"] }
        // Percentage preserves readable small ratios at the two-decimal log precision.
        if let ratio = (stats["stall_ratio"] as? Double) ?? (stats["stall_ratio"] as? NSNumber)?.doubleValue, ratio.isFinite {
            fields["stall_pct"] = "\(LogFormatter.formatValue(ratio * 100))%"
        }
        return Self(name: "playtime", level: .info, fields: fields)
    }
}
