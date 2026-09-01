import XCTest
@testable import MediaPlayerKit

final class QoSTrackerTests: XCTestCase {
    
    func testQoSMetricsCalculation() {
        let url = URL(string: "https://example.com/video.mp4")!
        let tracker = QoSAPMTracker(sessionID: "test-session-123", mediaURL: url, engineName: "KSMEPlayer")
        
        tracker.markPrepareStart()
        usleep(10000) // 10ms
        tracker.markFirstFrameRendered()
        
        tracker.markPlayStart()
        tracker.markBufferingStart()
        usleep(5000) // 5ms
        tracker.markBufferingEnd()
        
        tracker.markDroppedFrame()
        tracker.markDroppedFrame()
        
        let report = tracker.finish()
        XCTAssertEqual(report.sessionID, "test-session-123")
        XCTAssertEqual(report.mediaURL, url)
        XCTAssertEqual(report.stutterCount, 1)
        XCTAssertEqual(report.droppedFrames, 2)
        XCTAssertGreaterThan(report.firstFrameDuration, 5.0)
        
        let dict = report.toDictionary()
        XCTAssertEqual(dict["session_id"] as? String, "test-session-123")
        XCTAssertEqual(dict["stutter_count"] as? Int, 1)
    }
}
