import XCTest
@testable import MediaPlayerKit

final class PlayerStateMachineTests: XCTestCase {
    
    func testStateTransitions() {
        let player = MediaPlayerController()
        XCTAssertEqual(player.state, .idle)
        
        let sampleURL = URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!
        player.setMediaSource(url: sampleURL)
        
        // 验证进入 preparing 状态
        XCTAssertEqual(player.state, .preparing)
        
        player.pause()
        XCTAssertEqual(player.state, .paused)
        
        player.stop()
        XCTAssertEqual(player.state, .stopped)
    }
    
    func testPlayerConfigCloning() {
        let config = PlayerConfig()
        config.autoPlay = false
        config.isLoop = true
        config.maxBufferDuration = 60.0
        
        guard let cloned = config.copy() as? PlayerConfig else {
            XCTFail("Cloning failed")
            return
        }
        
        XCTAssertEqual(cloned.autoPlay, false)
        XCTAssertEqual(cloned.isLoop, true)
        XCTAssertEqual(cloned.maxBufferDuration, 60.0)
    }
}
