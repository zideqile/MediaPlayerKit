import Foundation

/// 全链路 APM 质量监控与卡顿度量追踪器
public final class QoSAPMTracker {
    private var report: PlayerQoSReport
    private var prepareStartTime: CFAbsoluteTime = 0
    private var playStartTime: CFAbsoluteTime = 0
    private var bufferingStartTime: CFAbsoluteTime = 0
    private var isFirstFrameRendered = false
    
    public init(sessionID: String, mediaURL: URL, engineName: String) {
        self.report = PlayerQoSReport(sessionID: sessionID, mediaURL: mediaURL, engineName: engineName)
    }
    
    public func markPrepareStart() {
        prepareStartTime = CFAbsoluteTimeGetCurrent()
    }
    
    public func markFirstFrameRendered() {
        guard !isFirstFrameRendered else { return }
        isFirstFrameRendered = true
        report.firstFrameDuration = (CFAbsoluteTimeGetCurrent() - prepareStartTime) * 1000
    }
    
    public func markPlayStart() {
        if playStartTime == 0 {
            playStartTime = CFAbsoluteTimeGetCurrent()
        }
    }
    
    public func markBufferingStart() {
        bufferingStartTime = CFAbsoluteTimeGetCurrent()
        report.stutterCount += 1
    }
    
    public func markBufferingEnd() {
        guard bufferingStartTime > 0 else { return }
        let duration = CFAbsoluteTimeGetCurrent() - bufferingStartTime
        report.totalStutterDuration += duration
        bufferingStartTime = 0
    }
    
    public func markDroppedFrame() {
        report.droppedFrames += 1
    }
    
    public func markError(code: Int, message: String) {
        report.errorCode = code
        report.errorMessage = message
    }
    
    public func finish() -> PlayerQoSReport {
        if playStartTime > 0 {
            report.totalPlayDuration = CFAbsoluteTimeGetCurrent() - playStartTime
        }
        return report
    }
}
