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
            fields["stalledTotalDuration"] = duration
            result.append(Self(name: "StalledSummaryInfoStatistics.summarize", level: .error, fields: fields))
        }
        if reason == "created" {
            var fields = context
            fields["elapsedMs"] = snapshot["create_ms"]
            fields["createOK"] = snapshot["createOK"]
            result.append(Self(name: "playerCreation", level: .info, fields: fields))
        }
        // Source/attempt transitions already produce command and failure logs. Do not
        // repeat those, their metrics, and all three cumulative scopes in one record.
        if ["switch", "replaced", "error", "ended"].contains(reason) {
            result.append(playtime(snapshot, scope: "attempt", reason: reason, context: context))
        } else if reason.hasPrefix("sessionEnded:") {
            result.append(playtime(snapshot, scope: "session", reason: reason, context: [:]))
        }
        return result
    }

    private static func playtime(_ snapshot: [String: Any], scope: String, reason: String,
                                 context: [String: Any]) -> PlaybackStatisticsLog {
        let stats = snapshot[scope] as? [String: Any] ?? [:]
        var fields = context
        fields["scope"] = scope
        fields["reason"] = reason
        fields["totalPlayTime"] = stats["play_ms"]
        // Percentage preserves readable small ratios at the two-decimal log precision.
        if let ratio = stats["stall_ratio"] as? NSNumber { fields["stall_pct"] = ratio.doubleValue * 100 }
        return Self(name: "playtime", level: .info, fields: fields)
    }
}
