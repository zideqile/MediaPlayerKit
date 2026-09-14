import Foundation

/// Native QoS uses the same state-driven, monotonic timing contract as facade statistics.
public final class QoSAPMTracker {
    private var report: PlayerQoSReport
    private let clock: () -> TimeInterval
    private var prepareStartTime: TimeInterval?
    private var timing = PlaybackTimeAccumulator()
    private var ended = false
    private var isFirstFrameRendered = false

    public convenience init(sessionID: String, mediaURL: URL, engineName: String) {
        self.init(sessionID: sessionID, mediaURL: mediaURL, engineName: engineName,
                  clock: { ProcessInfo.processInfo.systemUptime })
    }
    init(sessionID: String, mediaURL: URL, engineName: String, clock: @escaping () -> TimeInterval) {
        report = PlayerQoSReport(sessionID: sessionID, mediaURL: mediaURL, engineName: engineName)
        self.clock = clock
    }
    public func markPrepareStart() { prepareStartTime = clock() }
    public func markFirstFrameRendered() {
        guard !ended, !isFirstFrameRendered, let start = prepareStartTime else { return }
        isFirstFrameRendered = true
        report.firstFrameDuration = max(0, clock() - start) * 1000
    }
    public func markState(_ state: PlayerState) {
        guard !ended else { return }
        timing.transition(to: state, at: clock())
    }
    public func markPlayStart() { markState(.playing) }
    public func markBufferingStart() { markState(.buffering) }
    /// Closing buffering alone does not prove playback resumed.
    public func markBufferingEnd() { markState(.paused) }
    public func markDroppedFrame() { report.droppedFrames = max(0, report.droppedFrames) + 1 }
    public func markError(code: Int, message: String) {
        markState(.error)
        report.errorCode = code; report.errorMessage = message
    }
    public func updateMetrics(_ metrics: PlayerRuntimeMetrics?, size: CGSize) {
        if size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0,
           size.width < CGFloat(Int.max), size.height < CGFloat(Int.max) {
            report.videoWidth = Int(size.width); report.videoHeight = Int(size.height)
        }
        if let frames = metrics?.droppedVideoFrames, frames >= 0, frames <= Int64(Int.max) {
            report.droppedFrames = Int(frames)
        }
    }
    /// Read without terminating open intervals.
    public func snapshot() -> PlayerQoSReport {
        let values = timing.values(at: clock())
        report.totalPlayDuration = values.play
        report.totalStutterDuration = values.stall
        report.stutterCount = values.count
        return report
    }
    /// Idempotent finalization: repeated reports cannot extend the finished session.
    public func finish() -> PlayerQoSReport {
        if !ended { timing.transition(to: .stopped, at: clock()); ended = true }
        return snapshot()
    }
}
