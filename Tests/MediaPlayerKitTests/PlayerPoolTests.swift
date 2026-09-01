import XCTest
@testable import MediaPlayerKit

final class PlayerPoolTests: XCTestCase {
    
    func testPlayerPoolAcquireAndRecycle() {
        let pool = PlayerPoolManager.shared
        pool.maxPoolSize = 2
        pool.warmUp()
        
        let player1 = pool.dequeuePlayer()
        XCTAssertNotNil(player1)
        
        let player2 = pool.dequeuePlayer()
        XCTAssertNotNil(player2)
        XCTAssertTrue(player1 !== player2)
        
        // 归还并重置
        pool.recyclePlayer(player1)
        
        // 再次获取应优先复用刚归还的实例
        let player3 = pool.dequeuePlayer()
        XCTAssertTrue(player3 === player1)
    }
}
