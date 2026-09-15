import Foundation

public enum PlayerStatisticsEvents {
    /// Main-thread notification. userInfo contains the same immutable snapshot as onStatistics.
    public static let didUpdate = Notification.Name("MediaPlayerKit.PlaybackStatistics")
}

/// Shared timing contract: monotonic elapsed seconds; only playing contributes play time.
/// Snapshotting includes open intervals without closing or double counting them.
struct PlaybackTimeAccumulator {
    private var state: PlayerState = .idle
    private var since: TimeInterval?
    private var played: TimeInterval = 0
    private var stalled: TimeInterval = 0
    private var stalls = 0

    mutating func transition(to next: PlayerState, at time: TimeInterval) {
        guard time.isFinite, state != next else { return }
        if let start = since {
            let elapsed = max(0, time - start)
            if state == .playing { played += elapsed }
            if state == .buffering { stalled += elapsed }
        }
        if next == .buffering { stalls += 1 }
        state = next; since = time
    }
    func values(at time: TimeInterval) -> (play: Double, stall: Double, count: Int) {
        let elapsed = since.map { max(0, time - $0) } ?? 0
        return (played + (state == .playing ? elapsed : 0),
                stalled + (state == .buffering ? elapsed : 0), stalls)
    }
    func fields(at time: TimeInterval) -> [String: Any] {
        let value = values(at: time)
        let total = value.play + value.stall
        return ["play_ms": value.play * 1000, "stalledTotalDuration": value.stall * 1000,
                "stalledCount": value.count, "stall_ratio": total > 0 ? value.stall / total : 0]
    }
}

/// Bounded storage: one live attempt/source segment and cumulative session totals.
/// Records are cumulative snapshots, never additive upload deltas.
final class PlaybackStatisticsTracker {
    private let clock: () -> TimeInterval
    private var sessionID = UUID().uuidString
    private var sourceID = ""
    private var attemptID = ""
    private var sourceKey = ""
    private var sourceURL = ""
    private var sourceType = ""
    private var sourceIndex = 0
    private var engine = ""
    private var lifetime = PlaybackTimeAccumulator()
    private var lifetimeAttempts = 0
    private var finished = false
    private var session = PlaybackTimeAccumulator()
    private var source = PlaybackTimeAccumulator()
    private var attempt = PlaybackTimeAccumulator()
    private var active = false
    private var sessionStarted = false
    private var attemptStarted: TimeInterval = 0
    private var sequence = 0
    private var attemptCount = 0
    private var sourceSwitchCount = 0
    private var engineSwitchCount = 0
    private var errorCount = 0
    private var recoveryCount = 0
    private var recoverySuccessCount = 0
    private var recoveryFailureCount = 0
    private var recoveryCancelledCount = 0
    private var recoveryStarted: TimeInterval?
    private var recoveryDurationMs: Double?
    private var firstFrameMs: Double?
    private var creationMs: Double?
    private var creationOK = false
    private var lastError: [String: Any]?
    private var metrics: [String: Double] = [:]
    private var metricsSampleTime: Int64?
    private var lastWindow: (play: Double, stall: Double, count: Int) = (0, 0, 0)
    private(set) var latest: [String: Any] = [:]
    var emit: (([String: Any]) -> Void)?
    var requestScope = "engineAggregate"

    init(clock: @escaping () -> TimeInterval) { self.clock = clock }

    func begin(sourceURL: String, sourceType: String, sourceIndex: Int, engine: String) {
        guard !finished else { return }
        endAttempt(reason: "replaced")
        let key = "\(sourceIndex):\(sourceURL)"
        if key != sourceKey || sourceID.isEmpty {
            if !sourceID.isEmpty {
                publish(reason: "sourceEnded")
                sourceSwitchCount += 1
            }
            source = PlaybackTimeAccumulator(); sourceID = UUID().uuidString
        } else if !self.engine.isEmpty, self.engine != engine {
            engineSwitchCount += 1
        }
        self.sourceKey = key; self.sourceURL = sourceURL; self.sourceType = sourceType
        self.sourceIndex = sourceIndex; self.engine = engine
        attempt = PlaybackTimeAccumulator(); attemptID = UUID().uuidString
        attemptStarted = clock(); active = true; sessionStarted = true; attemptCount += 1; lifetimeAttempts += 1
        firstFrameMs = nil; creationMs = nil; creationOK = false; metrics = [:]; metricsSampleTime = nil; lastError = nil
    }
    func created() {
        guard active else { return }
        creationMs = max(0, clock() - attemptStarted) * 1000; creationOK = true
        publish(reason: "created")
    }
    func state(_ state: PlayerState) {
        guard active else { return }
        let time = clock()
        attempt.transition(to: state, at: time); source.transition(to: state, at: time)
        session.transition(to: state, at: time)
        lifetime.transition(to: state, at: time)
        if state == .playing, let start = recoveryStarted {
            recoveryDurationMs = max(0, time - start) * 1000
            recoverySuccessCount += 1; recoveryStarted = nil
            publish(reason: "recovered")
        } else if state == .completed {
            publish(reason: "ended")
        } else if state == .paused {
            publish(reason: "paused")
        } else if state == .buffering {
            publish(reason: "buffering")
        } else if state == .stopped {
            publish(reason: "stopped")
        }
    }
    func seek() {
        guard active else { return }
        publish(reason: "seek")
    }
    func firstFrame() {
        guard active, firstFrameMs == nil else { return }
        firstFrameMs = max(0, clock() - attemptStarted) * 1000
        publish(reason: "firstFrame")
    }
    func updateMetrics(_ fields: [String: Double]) {
        guard active else { return }
        metrics = fields.filter { $0.value.isFinite }
        metricsSampleTime = Int64(Date().timeIntervalSince1970 * 1000)
    }
    func failed(error: NSError, willRecover: Bool) {
        guard active else { return }
        errorCount += 1
        lastError = ["domain": error.domain, "code": error.code, "message": error.localizedDescription]
        if willRecover, recoveryStarted == nil { recoveryStarted = clock(); recoveryDurationMs = nil; recoveryCount += 1 }
        if !willRecover, let start = recoveryStarted {
            recoveryFailureCount += 1; recoveryDurationMs = max(0, clock() - start) * 1000
            recoveryStarted = nil
        }
        endAttempt(reason: "error")
    }
    func cancelRecovery() {
        if recoveryStarted != nil { recoveryCancelledCount += 1; recoveryStarted = nil }
    }
    func endAttempt(reason: String) {
        guard active else { return }
        let time = clock()
        attempt.transition(to: .stopped, at: time); source.transition(to: .stopped, at: time)
        session.transition(to: .stopped, at: time)
        lifetime.transition(to: .stopped, at: time)
        active = false
        publish(reason: reason, attemptEnded: true)
    }
    func finish(reason: String) {
        guard !finished else { return }
        if sessionStarted {
            cancelRecovery()
            endAttempt(reason: reason)
            publish(reason: "sessionEnded:" + reason)
            sessionStarted = false
        }
        if reason == "destroy" {
            publish(reason: "lifetimeEnded")
            finished = true
        }
    }
    func reset() {
        finish(reason: "newSources")
        sessionID = UUID().uuidString; sourceID = ""; attemptID = ""; sourceKey = ""; engine = ""
        session = PlaybackTimeAccumulator(); source = PlaybackTimeAccumulator(); attempt = PlaybackTimeAccumulator()
        attemptCount = 0; sourceSwitchCount = 0; engineSwitchCount = 0; errorCount = 0
        recoveryCount = 0; recoverySuccessCount = 0; recoveryFailureCount = 0; recoveryCancelledCount = 0
        recoveryDurationMs = nil; latest = [:]; lastWindow = (0, 0, 0)
    }
    static func isReportable(_ record: [String: Any]) -> Bool {
        guard let reason = record["reason"] as? String else { return true }
        if reason != "periodic" { return true }
        let window = record["window"] as? [String: Any]
        let stalledCount = (window?["stalledCount"] as? NSNumber)?.intValue ?? 0
        let stalledDuration = (window?["stalledTotalDuration"] as? NSNumber)?.doubleValue ?? 0
        return stalledCount > 0 || stalledDuration > 0
    }

    func publish(reason: String = "periodic", attemptEnded: Bool = false) {
        guard !finished, sessionStarted || (reason == "lifetimeEnded" && lifetimeAttempts > 0) else { return }
        let time = clock()
        let cumulative = session.values(at: time)
        let window: [String: Any] = ["play_ms": max(0, cumulative.play - lastWindow.play) * 1000,
            "stalledTotalDuration": max(0, cumulative.stall - lastWindow.stall) * 1000,
            "stalledCount": max(0, cumulative.count - lastWindow.count)]
        lastWindow = cumulative
        sequence += 1
        var record: [String: Any] = ["schemaVersion": 2, "sessionId": sessionID,
            "sourceId": sourceID, "attemptId": attemptID, "sequence": sequence,
            "time": Int64(Date().timeIntervalSince1970 * 1000), "reason": reason,
            "sourceUrl": sourceURL, "sourceType": sourceType, "sourceIndex": sourceIndex,
            "sourceDomain": URL(string: sourceURL)?.host ?? "", "engine": engine,
            "session": session.fields(at: time), "source": source.fields(at: time),
            "attempt": attempt.fields(at: time), "window": window,
            "attemptEnded": attemptEnded,
            "lifetime": lifetime.fields(at: time).merging(["attempts": lifetimeAttempts]) { _, new in new },
            "attempts": attemptCount, "source_switches": sourceSwitchCount,
            "engine_switches": engineSwitchCount, "errors": errorCount,
            "recoveries": recoveryCount, "recover_ok": recoverySuccessCount,
            "recover_fail": recoveryFailureCount, "recover_cancel": recoveryCancelledCount,
            "recovering": recoveryStarted != nil, "recover_ms": recoveryDurationMs.map { $0 as Any } ?? NSNull(),
            "first_frame_time": firstFrameMs.map { $0 as Any } ?? NSNull(),
            "create_ms": creationMs.map { $0 as Any } ?? NSNull(), "createOK": creationOK,
            "error": lastError.map { $0 as Any } ?? NSNull(), "metrics": metrics,
            "metrics_time": metricsSampleTime.map { $0 as Any } ?? NSNull(),
            "request_scope": requestScope, "request_details": requestScope == "hlsRequests"]
        record["reportable"] = Self.isReportable(record)
        latest = record; emit?(record)
    }
}
