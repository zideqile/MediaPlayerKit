import XCTest
@testable import MediaPlayerKit

final class PlayerAPITests: XCTestCase {
    
    func testExportVersionAndInit() {
        XCTAssertEqual(export.GetVersion(), SDKVersion.version)
        
        let initConfig = InitConfig()
        initConfig.appenders = [] // Unit tests must not contact the log service.
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
        XCTAssertEqual(player.GetCurrentTime(), 120)
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


private final class H5EventRecorder: NSObject, H5EventListener {
    var events: [String] = []
    var errors = 0
    var timeUpdates = 0
    func onEvent(_ eventName: String) { events.append(eventName) }
    func onError(_ code: Int, errMsg: String) { errors += 1 }
    func onTimeUpdate(_ currentTime: Int64) { timeUpdates += 1 }
}

extension PlayerAPITests {
    func testPartialConfigurationPreservesDefaults() throws {
        let config = try JSONDecoder().decode(VPlayerConfig.self, from: Data("""
        {"volume":0.5,"muted":true,"logConfig":{"level":3},"logServerConfig":{"domain":"example.com"}}
        """.utf8))
        XCTAssertEqual(config.volume, 0.5)
        XCTAssertTrue(config.muted)
        XCTAssertEqual(config.speed, 1)
        XCTAssertEqual(config.logConfig.level, 3)
        XCTAssertEqual(config.logConfig.uploadIntervalSeconds, 30)
        XCTAssertEqual(config.logServerConfig.domain, "example.com")
        XCTAssertEqual(config.logServerConfig.port, 443)
        XCTAssertTrue(config.logServerConfig.secure)
        XCTAssertEqual(VPlayerConfig.fromJson("{\"volume\":0.25}").volume, 0.25)
    }

    func testSourceJSONStringIncludesBothIndexContracts() throws {
        let source = PlayerSource(url: "https://example.com/live.m3u8")
        source.sourceIndex = 2
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(source.toJSONString().utf8)) as? [String: Any])
        XCTAssertEqual(json["index"] as? Int, 2)
        XCTAssertEqual(json["sourceIndex"] as? Int, 2)
        XCTAssertEqual(json["src"] as? String, source.url)
        XCTAssertEqual(json["url"] as? String, source.url)
    }

    func testH5EventsAcrossPauseEndAndReplay() {
        let run = {
            let player = H5Player(playerView: MediaPlayerView())
            let recorder = H5EventRecorder()
            player.SetOnH5EventListener(recorder)
            defer { player.destroy() }
            player.onStateChanged(state: .preparing)
            player.onStateChanged(state: .playing)
            player.onFirstFrameRendered()
            player.onStateChanged(state: .playing)
            XCTAssertEqual(recorder.events.filter { $0 == "playing" }.count, 1)
            player.onStateChanged(state: .paused)
            player.onFirstFrameRendered()
            XCTAssertEqual(recorder.events.last, "pause")
            player.onStateChanged(state: .completed)
            player.onPlayToEnd()
            XCTAssertEqual(recorder.events.filter { $0 == "ended" }.count, 1)
            player.onStateChanged(state: .playing)
            player.onPlayToEnd()
            player.onStateChanged(state: .completed)
            XCTAssertEqual(recorder.events.filter { $0 == "ended" }.count, 2)
        }
        if Thread.isMainThread { run() } else { DispatchQueue.main.sync(execute: run) }
    }

    func testEmptySourcesDoNotRestartHeartbeatAfterError() {
        let run = {
            let player = H5Player(playerView: MediaPlayerView())
            let recorder = H5EventRecorder()
            player.SetOnH5EventListener(recorder)
            defer { player.destroy() }
            player.play()
            RunLoop.main.run(until: Date().addingTimeInterval(0.65))
            XCTAssertEqual(recorder.errors, 0)
            XCTAssertEqual(recorder.events.filter { $0 == "PlayerWARN" }.count, 1)
            XCTAssertEqual(recorder.timeUpdates, 0)
        }
        if Thread.isMainThread { run() } else { DispatchQueue.main.sync(execute: run) }
    }

    func testContinuousSourceSwitchingAndIndexSafety() {
        let playerView = MediaPlayerView()
        let player = MultiSourcePlayer(playerView: playerView)
        let s1 = PlayerSource(url: "https://example.com/stream1.m3u8", type: "hls", tag: "line1")
        let s2 = PlayerSource(url: "https://example.com/stream2.flv", type: "flv", tag: "line2")
        let s3 = PlayerSource(url: "https://example.com/stream3.m3u8", type: "hls", tag: "line3")
        
        player.setSources([s1, s2, s3])
        XCTAssertEqual(player.currentSourceIndex, 0)
        XCTAssertEqual(player.getCurrentSource()?.tag, "line1")
        
        XCTAssertTrue(player.switchToSource(index: 1))
        XCTAssertEqual(player.currentSourceIndex, 1)
        XCTAssertEqual(player.getCurrentSource()?.tag, "line2")
        
        XCTAssertTrue(player.switchToSource(index: 2))
        XCTAssertEqual(player.currentSourceIndex, 2)
        XCTAssertEqual(player.getCurrentSource()?.tag, "line3")
        
        // Out of bounds checks
        XCTAssertFalse(player.switchToSource(index: 3))
        XCTAssertFalse(player.switchToSource(index: -1))
        XCTAssertFalse(player.switchToNextSource())
        
        // Switch back to start
        XCTAssertTrue(player.switchToSource(index: 0))
        XCTAssertEqual(player.currentSourceIndex, 0)
        player.Destroy()
    }

    func testH265SourceParsingFromDictionary() {
        // 1. Explicit Int 4
        let s1 = PlayerSource.fromDictionary(["src": "https://example.com/test.m3u8", "videoCodec": 4])
        XCTAssertEqual(s1.videoCodec, PlayerSource.CODEC_H265)

        // 2. String "4"
        let s2 = PlayerSource.fromDictionary(["src": "https://example.com/test.m3u8", "videoCodec": "4"])
        XCTAssertEqual(s2.videoCodec, PlayerSource.CODEC_H265)

        // 3. String "h265"
        let s3 = PlayerSource.fromDictionary(["src": "https://example.com/test.m3u8", "videoCodec": "h265"])
        XCTAssertEqual(s3.videoCodec, PlayerSource.CODEC_H265)

        // 4. "codec": "hevc"
        let s4 = PlayerSource.fromDictionary(["src": "https://example.com/test.m3u8", "codec": "hevc"])
        XCTAssertEqual(s4.videoCodec, PlayerSource.CODEC_H265)

        // 5. Inferred from url containing hevc when codec omitted
        let s5 = PlayerSource.fromDictionary(["src": "https://example.com/live_hevc.m3u8"])
        XCTAssertEqual(s5.videoCodec, PlayerSource.CODEC_H265)

        // 6. Inferred from type "hls_hevc"
        let s6 = PlayerSource.fromDictionary(["src": "https://example.com/stream.m3u8", "type": "hls_hevc"])
        XCTAssertEqual(s6.videoCodec, PlayerSource.CODEC_H265)

        // 7. Explicit H.264
        let s7 = PlayerSource.fromDictionary(["src": "https://example.com/stream.m3u8", "videoCodec": 2])
        XCTAssertEqual(s7.videoCodec, PlayerSource.CODEC_H264)
    }

    func testComputeEngineOrderForH265AndOtherFormats() {
        let playerView = MediaPlayerView()
        let player = MultiSourcePlayer(playerView: playerView)
        defer { player.Destroy() }

        // H.265 by codec -> mePlayer first, then avPlayer
        let h265Source = PlayerSource(url: "https://example.com/live.m3u8", videoCodec: PlayerSource.CODEC_H265)
        XCTAssertEqual(player.computeEngineOrder(for: h265Source), [.mePlayer, .avPlayer])

        // H.265 by HEVC tag -> mePlayer first
        let hevcTagSource = PlayerSource(url: "https://example.com/live.m3u8", tag: "HEVC-1080P")
        XCTAssertEqual(player.computeEngineOrder(for: hevcTagSource), [.mePlayer, .avPlayer])

        // H.265 by HEVC URL -> mePlayer first
        let hevcUrlSource = PlayerSource(url: "https://example.com/live_hevc.m3u8")
        XCTAssertEqual(player.computeEngineOrder(for: hevcUrlSource), [.mePlayer, .avPlayer])

        // FLV -> only mePlayer
        let flvSource = PlayerSource(url: "https://example.com/live.flv", type: "flv")
        XCTAssertEqual(player.computeEngineOrder(for: flvSource), [.mePlayer])

        // RTMP -> only mePlayer
        let rtmpSource = PlayerSource(url: "rtmp://example.com/live/stream")
        XCTAssertEqual(player.computeEngineOrder(for: rtmpSource), [.mePlayer])

        // Standard H.264 HLS -> avPlayer first, then mePlayer
        let h264Source = PlayerSource(url: "https://example.com/live.m3u8", type: "hls", videoCodec: PlayerSource.CODEC_H264)
        XCTAssertEqual(player.computeEngineOrder(for: h264Source), [.avPlayer, .mePlayer])
    }
}
