import XCTest
@testable import MediaPlayerKit

final class VZPlayerAPITests: XCTestCase {
    
    func testExportVersionAndInit() {
        XCTAssertEqual(VZPlayerExport.GetVersion(), "2")
        XCTAssertEqual(export.GetVersion(), "2")
        
        let initConfig = VZInitConfig()
        initConfig.userId = 12345
        initConfig.topicId = "topic_888"
        initConfig.deviceInfo = "iPhone 15 Pro, iOS 17.5"
        
        let configJson = """
        {
            "env": "prod",
            "volume": 0.8,
            "speed": 1.25,
            "muted": false
        }
        """
        
        VZPlayerExport.Init(initConfig: initConfig, configJson: configJson)
        export.Init(initConfig, configJson)
    }
    
    func testPlayerSourceModelAndJSON() {
        let source = VZPlayerSource(
            url: "https://p2.vzan.com/live/123.m3u8",
            type: VZPlayerSource.TYPE_HLS,
            tag: "main_stream",
            videoCodec: 1,
            sarNum: 16,
            sarDen: 9,
            orderno: 1,
            isLive: true,
            ext: "m3u8"
        )
        source.sourceIndex = 0
        
        let jsonStr = source.toJSONString()
        XCTAssertTrue(jsonStr.contains("123.m3u8"))
        XCTAssertTrue(jsonStr.contains("\"type\":\"hls\""))
        XCTAssertTrue(jsonStr.contains("\"videoCodec\":1"))
        
        let dict = source.toDictionary()
        let restored = VZPlayerSource.fromDictionary(dict)
        XCTAssertEqual(restored.url, source.url)
        XCTAssertEqual(restored.type, source.type)
        XCTAssertEqual(restored.videoCodec, source.videoCodec)
        XCTAssertEqual(restored.isLive, source.isLive)
    }
    
    func testH5PlayerPropertiesGettersAndSetters() {
        let playerView = MediaPlayerView()
        let player = export.CreateVZPlayer(playerView)
        
        // 1. Volume
        XCTAssertTrue(player.set_volume("{\"volume\": 0.65}"))
        let volJson = player.get_volume()
        XCTAssertTrue(volJson.contains("0.65"))
        
        // 2. Muted
        XCTAssertTrue(player.set_muted("{\"muted\": true}"))
        let mutedJson = player.get_muted()
        XCTAssertTrue(mutedJson.contains("true"))
        
        // 3. Speed
        XCTAssertTrue(player.set_speed("{\"speed\": 1.5}"))
        let speedJson = player.get_speed()
        XCTAssertTrue(speedJson.contains("1.5"))
        
        // 4. Loop
        XCTAssertTrue(player.set_loop("{\"loop\": true}"))
        let loopJson = player.get_loop()
        XCTAssertTrue(loopJson.contains("true"))
        
        // 5. Seek
        XCTAssertTrue(player.set_currentTime("{\"currentTime\": 45}"))
        
        // 6. Sources
        let s1 = VZPlayerSource(url: "https://example.com/live1.m3u8", type: "hls")
        let s2 = VZPlayerSource(url: "https://example.com/live2.flv", type: "flv")
        player.setSources([s1, s2])
        
        let currentSourceJson = player.get_currentsource()
        XCTAssertTrue(currentSourceJson.contains("live1.m3u8"))
        
        // 7. Buffered & Duration & Pause
        XCTAssertFalse(player.get_buffered().isEmpty)
        XCTAssertFalse(player.get_duration().isEmpty)
        XCTAssertFalse(player.get_pause().isEmpty)
        
        // 8. Dynamic Source Switch
        let newSource = VZPlayerSource(url: "https://example.com/new_live.m3u8", type: "hls")
        player.setSources([newSource])
        let updatedSourceJson = player.get_currentsource()
        XCTAssertTrue(updatedSourceJson.contains("new_live.m3u8"))
        
        player.destroy()
    }
}
