import XCTest
@testable import MediaPlayerKit

final class PlayerAPITests: XCTestCase {
    
    func testExportVersionAndInit() {
        XCTAssertEqual(export.GetVersion(), "2")
        
        let initConfig = InitConfig()
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
        
        export.Init(initConfig, configJson)
    }
    
    func testPlayerSourceModelAndJSON() {
        let source = PlayerSource(
            url: "https://p2.vzan.com/live/123.m3u8",
            type: PlayerSource.TYPE_HLS,
            tag: "main_stream",
            videoCodec: PlayerSource.CODEC_H264,
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
        XCTAssertTrue(jsonStr.contains("\"videoCodec\":2"))
        
        let dict = source.toDictionary()
        let restored = PlayerSource.fromDictionary(dict)
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
        let s1 = PlayerSource(url: "https://example.com/live1.m3u8", type: "hls")
        let s2 = PlayerSource(url: "https://example.com/live2.flv", type: "flv")
        player.setSources([s1, s2])
        
        let currentSourceJson = player.get_currentsource()
        XCTAssertTrue(currentSourceJson.contains("live1.m3u8"))
        
        // 7. Buffered & Duration & Pause
        XCTAssertFalse(player.get_buffered().isEmpty)
        XCTAssertFalse(player.get_duration().isEmpty)
        XCTAssertFalse(player.get_pause().isEmpty)
        
        // 8. Dynamic Source Switch
        let newSource = PlayerSource(url: "https://example.com/new_live.m3u8", type: "hls")
        player.setSources([newSource])
        let updatedSourceJson = player.get_currentsource()
        XCTAssertTrue(updatedSourceJson.contains("new_live.m3u8"))
        
        player.destroy()
    }
    
    func testIPlayerAlignedAPIs() {
        let playerView = MediaPlayerView()
        let player: IPlayer = export.CreateVZPlayer(playerView) as! IPlayer
        
        let s1 = PlayerSource(url: "https://example.com/live1.m3u8", type: "hls")
        let s2 = PlayerSource(url: "https://example.com/live2.flv", type: "flv")
        
        // 1. Play with sources
        let playResult = player.Play([s1, s2])
        XCTAssertTrue(playResult)
        
        // 2. Volume & Mute
        player.SetVolume(0.75)
        XCTAssertEqual(player.GetVolume(), 0.75, accuracy: 0.01)
        player.SetMuted(true)
        XCTAssertTrue(player.IsMuted())
        player.SetMuted(false)
        XCTAssertFalse(player.IsMuted())
        
        // 3. Speed & Loop
        player.SetSpeed(1.25)
        XCTAssertEqual(player.GetSpeed(), 1.25, accuracy: 0.01)
        player.SetLoop(true)
        XCTAssertTrue(player.IsLoop())
        player.SetLoop(false)
        XCTAssertFalse(player.IsLoop())
        
        // 4. Seek & Time
        player.Seek(120)
        XCTAssertEqual(player.GetCurrentTime(), 0) // initial idle
        XCTAssertEqual(player.GetDuration(), 0)
        
        // 5. Buffer & Source
        let bufferRange = player.GetBuffered()
        XCTAssertEqual(bufferRange.length, 1)
        XCTAssertNotNil(player.getCurrentSource())
        
        // 6. Pause, Resume, Destroy
        player.Pause()
        XCTAssertTrue(player.IsPaused())
        player.Resume()
        player.Destroy()
    }
}


