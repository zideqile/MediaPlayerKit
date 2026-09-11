import XCTest
@testable import MediaPlayerKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class RecordingAppender: Appender {
    var messages: [String] = []
    var stats: [Double] = []
    var sources: [String] = []
    func append(level: LogLevel, tag: String, message: String, messageType: MessageType) { messages.append(message) }
    func appendStatLog(level: LogLevel, tag: String, name: String, data: Double) { stats.append(data) }
    func onSourceChanged(srcUrl: String, srcType: String) { sources.append(srcUrl) }
}
private final class RecordingUploader: ESUploader {
    var records: [[String: Any]] = []
    func upload(record: [String: Any], completion: @escaping (Bool) -> Void) { records.append(record); completion(true) }
}
private final class MockLogTransport: LogHTTPTransport {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    var responses: [Result<Data, Error>] = []
    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }
    func send(_ request: URLRequest, completion: @escaping (Result<Data, Error>) -> Void) {
        lock.lock()
        _requests.append(request)
        let resp = responses.isEmpty ? .success(Data()) : responses.removeFirst()
        lock.unlock()
        completion(resp)
    }
}
final class LoggingTests: XCTestCase {
    override func tearDown() { Logger.destroy(); super.tearDown() }
    func testLevelAndStatisticsContract() {
        let appender = RecordingAppender()
        let logger = InternalLogger(logGroup: "test", level: .warn)
        logger.addAppender(appender)
        logger.logI("hidden"); logger.logE("visible"); logger.logSD("fps", 30)
        XCTAssertEqual(appender.messages.map { $0.components(separatedBy: "] ").dropFirst().joined(separator: "] ") }, ["visible"])
        XCTAssertEqual(appender.stats, [30])
        XCTAssertEqual(LogConfig().level, 1)
        logger.destroy(); logger.logF("ignored")
        XCTAssertEqual(appender.messages.count, 1)
    }
    func testCustomAppenderAppliesToExistingAndFutureGroups() {
        Logger.configure { _ in [] }
        let first = Logger.getLogger("first")
        let appender = RecordingAppender()
        Logger.addAppender(appender); Logger.addAppender(appender)
        first.logI("one"); Logger.getLogger("second").logI("two")
        Logger.removeAppender(appender); first.logI("hidden")
        XCTAssertEqual(appender.messages.map { $0.components(separatedBy: "] ").dropFirst().joined(separator: "] ") }, ["one", "two"])
    }
    func testMergerFlushAndSimilarity() {
        let appender = RecordingAppender()
        let merger = LogMerger(delayMs: 60000, appender: appender)
        for _ in 0..<3 { merger.pushLog(level: .info, tag: "x", messageType: .log, similarity: 100, format: "frame {}", args: [10]) }
        merger.flush(); merger.flush(); merger.destroy()
        XCTAssertEqual(appender.messages, ["frame 10 [x3]"])
        XCTAssertEqual(LogMerger.similarity([100], [90]), 90)
        XCTAssertEqual(LogMerger.similarity(["abc"], ["abc"]), 100)
        XCTAssertEqual(LogMerger.formatBraces("{} {}", ["{}", 2]), "{} 2")
    }
    func testRecordFieldsAndSourceBoundary() {
        let config = VPlayerConfig(); config.userId = 42
        let uploader = RecordingUploader()
        var policy = LogUploadPolicy(); policy.uploadIntervalSeconds = 600
        let appender = ESUploadAppender(context: LogContext(config: config), policy: policy, uploader: uploader)
        appender.onSourceChanged(srcUrl: "https://old.example/live", srcType: "hls")
        appender.append(level: .warn, tag: "default", message: "old message", messageType: .log)
        appender.appendStatLog(level: .debug, tag: "default", name: "fps", data: 30)
        appender.onSourceChanged(srcUrl: "https://new.example/live", srcType: "hls")
        let record = uploader.records.first!
        XCTAssertEqual(record["userId"] as? Int64, 42)
        XCTAssertEqual((record["currentPlayerInfo"] as? [String: String])?["srcDomain"], "old.example")
        XCTAssertTrue((record["logs"] as? String)?.contains("warn old message") == true)
        XCTAssertEqual(record["logLevels"] as? String, "WARN,")
        XCTAssertEqual((record["statLogs"] as? [String: [Double]])?["fps"], [30])
        XCTAssertNotNil((record["globalPlayerInfo"] as? [String: Any])?["optionInfo"])
        appender.destroy()
    }
    func testOldUploadContract() throws {
        let transport = MockLogTransport()
        let uploader = try OldESUploader(server: LogServerConfig(), env: "test", transport: transport)
        uploader.upload(record: ["index": 0]) { XCTAssertTrue($0) }
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertTrue(request.url!.absoluteString.contains("bury_content=stream_VPlayerLog-test_stat"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: request.httpBody!) as? [[String: Any]])
    }
    func testNewUploadDiscoveryAndCache() throws {
        let transport = MockLogTransport()
        transport.responses = [.success(Data("""
        {"isok":true,"code":0,"dataObj":[{"type":2,"expires":200,"now":100,"url":"https://upload.example/record"}]}
        """.utf8))]
        let uploader = try NewESUploader(env: "test", topicId: "a&b", userId: "42", streamId: "s", clusterDomain: "example.com", authorization: { "token" }, transport: transport)
        let exp1 = expectation(description: "upload 0")
        uploader.upload(record: ["index": 0]) { XCTAssertTrue($0); exp1.fulfill() }
        wait(for: [exp1], timeout: 2)
        let exp2 = expectation(description: "upload 1")
        uploader.upload(record: ["index": 1]) { XCTAssertTrue($0); exp2.fulfill() }
        wait(for: [exp2], timeout: 2)
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Authorization"), "token")
        XCTAssertEqual(URLComponents(url: transport.requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "a&b")
        XCTAssertNil(transport.requests[1].value(forHTTPHeaderField: "Authorization"))
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: transport.requests[1].httpBody!) as? [String: Any])
    }
    func testFileAppenderAndDestroy() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let appender = try FileAppender(fileURL: url)
        appender.append(level: .info, tag: "test", message: "persisted", messageType: .log)
        appender.flush(); appender.destroy(); appender.destroy()
        XCTAssertTrue(try String(contentsOf: url).contains("persisted"))
    }
    func testInitializeHasNoNetworkSideEffect() throws {
        let transport = MockLogTransport()
        try Logger.initialize(config: VPlayerConfig(), initConfig: InitConfig(), transport: transport)
        XCTAssertTrue(transport.requests.isEmpty)
        Logger.destroy()
    }
    func testOnSourceChangedBroadcastsToAllLoggers() {
        let appenderA = RecordingAppender()
        let appenderB = RecordingAppender()
        Logger.configure { group in
            if group == "groupA" { return [appenderA] }
            if group == "groupB" { return [appenderB] }
            return []
        }
        _ = Logger.getLogger("groupA")
        _ = Logger.getLogger("groupB")
        Logger.onSourceChanged(srcUrl: "https://example.com/live.m3u8", srcType: "hls")
        XCTAssertEqual(appenderA.sources, ["https://example.com/live.m3u8"])
        XCTAssertEqual(appenderB.sources, ["https://example.com/live.m3u8"])
        Logger.destroy()
    }
    func testOnSourceChangedAppliesToLaterCreatedLoggers() {
        let appender = RecordingAppender()
        Logger.configure { _ in [appender] }
        Logger.onSourceChanged(srcUrl: "https://example.com/late.m3u8", srcType: "hls")
        let lateLogger = Logger.getLogger("lateGroup")
        lateLogger.logI("ping")
        XCTAssertEqual(appender.sources, ["https://example.com/late.m3u8"])
        Logger.destroy()
    }
    func testNewUploadDiscoveryWithMillisecondTimestamps() throws {
        let transport = MockLogTransport()
        transport.responses = [.success(Data("""
        {"isok":true,"code":0,"dataObj":[{"type":2,"expires":1700007200000,"now":1700000000000,"url":"https://upload.example/record"}]}
        """.utf8))]
        let uploader = try NewESUploader(env: "test", topicId: "a", userId: "42", streamId: "s", clusterDomain: "example.com", authorization: { "token" }, transport: transport)
        let exp1 = expectation(description: "upload 0")
        uploader.upload(record: ["index": 0]) { XCTAssertTrue($0); exp1.fulfill() }
        wait(for: [exp1], timeout: 2)
        let exp2 = expectation(description: "upload 1")
        uploader.upload(record: ["index": 1]) { XCTAssertTrue($0); exp2.fulfill() }
        wait(for: [exp2], timeout: 2)
        XCTAssertEqual(transport.requests.count, 3)
        let refreshInterval = uploader.cachedRefreshAt.timeIntervalSinceNow
        XCTAssertGreaterThan(refreshInterval, 3500)
        XCTAssertLessThan(refreshInterval, 3700)
    }
    func testNewUploadDiscoveryWithShortMillisecondValidity() throws {
        let transport = MockLogTransport()
        // diff is 60_000 ms (60 seconds).
        transport.responses = [.success(Data("""
        {"isok":true,"code":0,"dataObj":[{"type":2,"expires":1700000060000,"now":1700000000000,"url":"https://upload.example/record"}]}
        """.utf8))]
        let uploader = try NewESUploader(env: "test", topicId: "a", userId: "42", streamId: "s", clusterDomain: "example.com", authorization: { "token" }, transport: transport)
        let exp1 = expectation(description: "first upload done")
        uploader.upload(record: ["index": 0]) { _ in exp1.fulfill() }
        wait(for: [exp1], timeout: 2)
        let exp2 = expectation(description: "second upload done")
        uploader.upload(record: ["index": 1]) { _ in exp2.fulfill() }
        wait(for: [exp2], timeout: 2)
        XCTAssertEqual(transport.requests.count, 3)
        let refreshInterval = uploader.cachedRefreshAt.timeIntervalSinceNow
        // Must be ~30 seconds, definitely not 30,000 seconds!
        XCTAssertGreaterThan(refreshInterval, 20)
        XCTAssertLessThan(refreshInterval, 40)
    }
    func testConcurrentUploadsDoNotBlockDuringAuthorization() throws {
        let transport = MockLogTransport()
        transport.responses = [.success(Data("""
        {"isok":true,"code":0,"dataObj":[{"type":2,"expires":200,"now":100,"url":"https://upload.example/record"}]}
        """.utf8))]
        let authEntered = DispatchSemaphore(value: 0)
        let canFinishAuth = DispatchSemaphore(value: 0)
        let uploader = try NewESUploader(env: "test", topicId: "a", userId: "1", streamId: "s", clusterDomain: "example.com", authorization: {
            authEntered.signal()
            _ = canFinishAuth.wait(timeout: .now() + 2)
            return "token"
        }, transport: transport)

        let exp1 = expectation(description: "upload 1")
        uploader.upload(record: ["index": 1]) { XCTAssertTrue($0); exp1.fulfill() }
        _ = authEntered.wait(timeout: .now() + 1)

        // Upload 2 while authorization is still running: must not block caller!
        let exp2 = expectation(description: "upload 2")
        uploader.upload(record: ["index": 2]) { XCTAssertTrue($0); exp2.fulfill() }

        // Let auth finish
        canFinishAuth.signal()
        wait(for: [exp1, exp2], timeout: 3)
        XCTAssertEqual(transport.requests.count, 3)
    }
    func testLogTimeFormatting() {
        let formatted = logTime(Date(timeIntervalSince1970: 0))
        XCTAssertEqual(formatted.count, 12) // HH:mm:ss.SSS is 12 chars
        XCTAssertTrue(formatted.contains(":"))
        XCTAssertTrue(formatted.contains("."))
    }
}

private final class ControlledUploader: ESUploader {
    private let executor = LogExecutor()
    private var attempts: [Int] = []
    private var callback: ((Bool) -> Void)?
    var onAttempt: (() -> Void)?
    var indices: [Int] { executor.sync { attempts } }
    func upload(record: [String: Any], completion: @escaping (Bool) -> Void) {
        executor.sync { attempts.append(record["index"] as! Int); callback = completion }
        onAttempt?()
    }
    func complete(_ success: Bool) {
        let completion = executor.sync { () -> ((Bool) -> Void)? in
            let result = callback; callback = nil; return result
        }
        completion?(success)
    }
}
extension LoggingTests {
    func testBoundedQueueRetainsInFlightRecord() {
        let uploader = ControlledUploader()
        let task = StatisticsUploadTask(uploader: uploader, capacity: 2)
        task.upload(["index": 0]); task.upload(["index": 1]); task.upload(["index": 2]); task.upload(["index": 3])
        XCTAssertEqual(task.innerDrop, 1)
        XCTAssertEqual(uploader.indices, [0])
        let sent = expectation(description: "next retained record")
        uploader.onAttempt = { sent.fulfill() }
        uploader.complete(true)
        wait(for: [sent], timeout: 2)
        XCTAssertEqual(uploader.indices, [0, 2])
        task.stop(); uploader.complete(true)
    }
    func testFailedUploadRetriesWithoutNewLogs() {
        let uploader = ControlledUploader()
        let task = StatisticsUploadTask(uploader: uploader)
        task.upload(["index": 0])
        let retried = expectation(description: "scheduled retry")
        uploader.onAttempt = { retried.fulfill() }
        uploader.complete(false)
        wait(for: [retried], timeout: 3)
        XCTAssertEqual(uploader.indices, [0, 0])
        task.stop(); uploader.complete(true)
    }
}

private final class MergeableAppender: Appender {
    var messages: [String] = []
    func makeLogMerger() -> LogMerger? { LogMerger(delayMs: 60000, appender: self) }
    func append(level: LogLevel, tag: String, message: String, messageType: MessageType) { messages.append(message) }
}

extension LoggingTests {
    func testRuntimeStateConfigurationDefaultsAndPartialDecoding() throws {
        let config = try JSONDecoder().decode(VPlayerConfig.self, from: Data("{\"runtimeStateCollect\":{\"stateCountLimit\":2}}".utf8))
        XCTAssertEqual(config.runtimeStateCollect.stateCountLimit, 2)
        XCTAssertEqual(config.runtimeStateCollect.collectIntervalSeconds, 3)
        XCTAssertEqual(VPlayerConfig.fromJson("{}").runtimeStateCollect.stateCountLimit, 10)
        let restored = try JSONDecoder().decode(VPlayerConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(restored.runtimeStateCollect.stateCountLimit, 2)
    }

    func testInitializeUsesConfiguredAttachedLogCapacity() throws {
        let config = VPlayerConfig()
        config.runtimeStateCollect.stateCountLimit = 2
        let options = InitConfig(); options.appenders = ["ESAppender"]
        let transport = MockLogTransport()
        try Logger.initialize(config: config, initConfig: options, transport: transport)
        Logger.logAI("first"); Logger.logAI("second"); Logger.logAI("third")
        Logger.logI("trigger"); Logger.flushLog()
        let body = try XCTUnwrap(transport.requests.first?.httpBody)
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        let attached = try XCTUnwrap(records.first?["attachedLogs"] as? String)
        XCTAssertFalse(attached.contains("first"))
        XCTAssertTrue(attached.contains("second"))
        XCTAssertTrue(attached.contains("third"))
    }

    func testStatisticsRetainEntireUploadPeriod() {
        let uploader = RecordingUploader()
        var policy = LogUploadPolicy(); policy.uploadIntervalSeconds = 600
        let appender = ESUploadAppender(context: LogContext(config: VPlayerConfig()), policy: policy, uploader: uploader)
        defer { appender.destroy() }
        for value in 0..<50 { appender.appendStatLog(level: .info, tag: "test", name: "fps", data: Double(value)) }
        appender.flushIfNeeded() // not expired: must retain all samples
        XCTAssertTrue(uploader.records.isEmpty)
        appender.append(level: .info, tag: "test", message: "trigger", messageType: .log)
        appender.flushIfNeeded()
        XCTAssertEqual((uploader.records.first?["statLogs"] as? [String: [Double]])?["fps"], (0..<50).map(Double.init))
    }

    func testAttachedStatisticsTrimOnlyWhenWaitingForOrdinaryLogs() {
        let uploader = RecordingUploader()
        var policy = LogUploadPolicy(); policy.uploadIntervalSeconds = 600
        policy.statLogIsAttachedToLog = true
        let appender = ESUploadAppender(context: LogContext(config: VPlayerConfig()), policy: policy, uploader: uploader)
        defer { appender.destroy() }
        for value in 0..<50 { appender.appendStatLog(level: .info, tag: "test", name: "fps", data: Double(value)) }
        appender.flushIfNeeded()
        XCTAssertTrue(uploader.records.isEmpty)
        appender.appendStatLog(level: .info, tag: "test", name: "fps", data: 50)
        appender.append(level: .info, tag: "test", message: "trigger", messageType: .log)
        appender.flushIfNeeded()
        XCTAssertEqual((uploader.records.first?["statLogs"] as? [String: [Double]])?["fps"], (20...50).map(Double.init))
    }

    func testOptionalStatisticCapCountsDroppedSamples() {
        let uploader = RecordingUploader()
        var policy = LogUploadPolicy(); policy.uploadIntervalSeconds = 600
        policy.maxStatisticSamplesPerName = 2
        let appender = ESUploadAppender(context: LogContext(config: VPlayerConfig()), policy: policy, uploader: uploader)
        defer { appender.destroy() }
        for value in 0..<5 { appender.appendStatLog(level: .info, tag: "test", name: "fps", data: Double(value)) }
        appender.flush()
        XCTAssertEqual((uploader.records.first?["statLogs"] as? [String: [Double]])?["fps"], [3, 4])
        XCTAssertEqual(uploader.records.first?["innerDrop"] as? Int, 3)
    }

    func testCustomAppenderMergerOwnershipAcrossGroups() {
        let appender = MergeableAppender()
        let first = InternalLogger(logGroup: "first")
        let second = InternalLogger(logGroup: "second")
        first.addAppender(appender); second.addAppender(appender)
        func emit(_ logger: InternalLogger, _ value: Int) { logger.logMI(100, "frame {}", value) }
        emit(first, 1); emit(first, 1)
        emit(second, 2)
        XCTAssertTrue(appender.messages.isEmpty)
        first.removeAppender(appender) // flush and destroy only first group's merger
        XCTAssertEqual(appender.messages.map { $0.components(separatedBy: "] ").dropFirst().joined(separator: "] ") }, ["frame 1 [x2]"])
        emit(second, 2)
        second.flushLog(); second.flushLog()
        XCTAssertEqual(appender.messages.map { $0.components(separatedBy: "] ").dropFirst().joined(separator: "] ") }, ["frame 1 [x2]", "frame 2 [x2]"])
        first.destroy(); second.destroy()
    }
}

private final class DiagnosticsRecorder: Appender {
    var messages: [String] = []
    var values: [String: [Double]] = [:]
    var source = ""
    var finishes = 0
    func append(level: LogLevel, tag: String, message: String, messageType: MessageType) { messages.append(message) }
    func appendStatLog(level: LogLevel, tag: String, name: String, data: Double) { values[name, default: []].append(data) }
    func onSourceChanged(srcUrl: String, srcType: String) { source = srcUrl }
    func finish() { finishes += 1 }
}
extension LoggingTests {
    func testPlaybackDiagnosticsTimingsAndFailureFields() {
        let recorder = DiagnosticsRecorder()
        Logger.configure { _ in [recorder] }
        var time: TimeInterval = 10
        let diagnostics = PlaybackDiagnostics(group: "test-player", clock: { time })
        let source = PlayerSource(url: "https://example.com/live.m3u8", videoCodec: PlayerSource.CODEC_H265)
        diagnostics.sources([source])
        diagnostics.begin(source: source, engine: .mePlayer)
        time = 10.25
        diagnostics.firstFrame(size: CGSize(width: 100, height: 100))
        diagnostics.firstFrame(size: .zero)
        XCTAssertEqual(recorder.values["first_frame_time"], [250])
        XCTAssertEqual(recorder.values["source_hls_hevc"], [1])
        time = 11; diagnostics.state(.buffering)
        time = 11.5; diagnostics.state(.buffering) // duplicate must not reset the start
        time = 12; diagnostics.state(.playing)
        XCTAssertEqual(recorder.values["ios_stall_episode_ms"], [1000])
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        diagnostics.failed(PlaybackAttemptFailure(sourceIndex: 0, sourceURL: source.url, engine: .mePlayer,
            category: .timeout, error: error, action: .nextEngine))
        XCTAssertEqual(recorder.values["player_time"], [2000])
        XCTAssertEqual(recorder.values["ios_player_ksmeplayer_error_code"], [Double(NSURLErrorTimedOut)])
        XCTAssertNil(recorder.values["player_type"])
        diagnostics.finish(); diagnostics.finish()
        XCTAssertEqual(recorder.finishes, 1)
    }
    func testPlayerGroupsKeepSourcesSeparate() {
        let first = DiagnosticsRecorder(), second = DiagnosticsRecorder()
        Logger.configure { $0 == "first" ? [first] : [second] }
        let a = PlaybackDiagnostics(group: "first"), b = PlaybackDiagnostics(group: "second")
        a.begin(source: PlayerSource(url: "https://a.example/live"), engine: .avPlayer)
        b.begin(source: PlayerSource(url: "https://b.example/live"), engine: .mePlayer)
        XCTAssertEqual(first.source, "https://a.example/live")
        XCTAssertEqual(second.source, "https://b.example/live")
        a.finish()
        XCTAssertEqual(first.finishes, 1)
        XCTAssertEqual(second.finishes, 0)
        b.command("still playing")
        XCTAssertTrue(second.messages.contains { $0.hasSuffix("] still playing") })
        b.finish()
    }
    func testUploadDrainWaitsForInflightRequest() {
        let uploader = ControlledUploader()
        let task = StatisticsUploadTask(uploader: uploader)
        task.upload(["index": 0])
        let finished = expectation(description: "drained")
        task.finish(timeout: 2) { finished.fulfill() }
        task.upload(["index": 1]) // no new records after close starts
        uploader.complete(true)
        wait(for: [finished], timeout: 3)
        XCTAssertEqual(uploader.indices, [0])
    }
    func testUploadDrainHasDeadline() {
        let uploader = ControlledUploader()
        let task = StatisticsUploadTask(uploader: uploader)
        task.upload(["index": 0])
        let finished = expectation(description: "drain timed out")
        task.finish(timeout: 0.05) { finished.fulfill() }
        wait(for: [finished], timeout: 2)
        uploader.complete(false)
        task.stop()
    }
    func testExternalAppenderConfiguredThroughInitOptions() throws {
        let recorder = DiagnosticsRecorder()
        let options = InitConfig(); options.appenders = []; options.externalAppenders = [recorder]
        try Logger.initialize(config: VPlayerConfig(), initConfig: options)
        Logger.logI("custom sink")
        XCTAssertEqual(recorder.messages.map { $0.components(separatedBy: "] ").dropFirst().joined(separator: "] ") }, ["custom sink"])
        Logger.destroy()
        XCTAssertEqual(recorder.finishes, 0) // caller owns external outputs
    }
}


extension LoggingTests {
    func testCallerLocationSurvivesConvenienceWrappers() {
        let recorder = DiagnosticsRecorder()
        Logger.configure { _ in [recorder] }
        let line = #line + 1
        Logger.logI("static", typeName: "LoggingTests")
        XCTAssertEqual(recorder.messages.last, "[LoggingTests.\(#function):\(line)] static")
        let logger = Logger.getLogger("location")
        let instanceLine = #line + 1
        logger.logAI("attached", typeName: "LoggingTests")
        XCTAssertEqual(recorder.messages.last, "[LoggingTests.\(#function):\(instanceLine)] attached")
        let diagnostics = PlaybackDiagnostics(group: "forwarding")
        diagnostics.command("pause", fileID: "SDK/MultiSourcePlayer.swift", function: "pause()", line: 123)
        XCTAssertEqual(recorder.messages.last, "[MultiSourcePlayer.pause():123] pause")
        logger.logSI("fps", 25)
        XCTAssertEqual(recorder.values["fps"], [25])
    }

    func testMergeKeepsDistinctCallerLocations() {
        let appender = MergeableAppender()
        let logger = InternalLogger(logGroup: "merge")
        logger.addAppender(appender)
        for line: UInt in [10, 10, 20] {
            logger.logMI(100, "frame {}", 1, fileID: "SDK/Player.swift", function: "render()", line: line)
        }
        logger.flushLog()
        XCTAssertEqual(appender.messages, ["[Player.render():10] frame 1 [x2]", "[Player.render():20] frame 1"])
    }

    func testRuntimeCounterDeltasAndUnavailableMeasurements() {
        var sampler = RuntimeMetricsSampler()
        var metrics = PlayerRuntimeMetrics()
        metrics.displayFPS = 0; metrics.nominalFrameRate = .nan; metrics.bytesRead = 100
        let first = sampler.sample(metrics, at: 10)
        XCTAssertEqual(first["fps"], 0)
        XCTAssertNil(first["frame_rate"])
        XCTAssertNil(first["ios_bytes_read_delta"])
        metrics.bytesRead = 700
        XCTAssertEqual(sampler.sample(metrics, at: 13)["ios_bytes_read_per_second"], 200)
        metrics.bytesRead = 20
        XCTAssertNil(sampler.sample(metrics, at: 16)["ios_bytes_read_delta"])
        metrics.bytesRead = nil
        XCTAssertNil(sampler.sample(metrics, at: 19)["ios_bytes_read_delta"])
        metrics.bytesRead = 900
        XCTAssertNil(sampler.sample(metrics, at: 22)["ios_bytes_read_delta"])
        metrics.displayFPS = -1; metrics.observedBitrate = .infinity
        XCTAssertTrue(sampler.sample(metrics, at: 25).values.allSatisfy { $0.isFinite && $0 >= 0 })
    }

    func testRuntimeSamplingThrottleAndPauseReset() {
        let recorder = DiagnosticsRecorder()
        Logger.configure { _ in [recorder] }
        var time: TimeInterval = 0
        let diagnostics = PlaybackDiagnostics(group: "metrics", clock: { time })
        let source = PlayerSource(url: "https://example.com/live")
        diagnostics.begin(source: source, engine: .mePlayer)
        diagnostics.state(.playing)
        var reads = 0
        func sample(_ interval: Double = 3) {
            diagnostics.sampleMetrics(interval: interval, provider: {
                reads += 1
                var metrics = PlayerRuntimeMetrics()
                metrics.bytesRead = Int64(time * 100); metrics.displayFPS = 24
                return metrics
            })
        }
        sample(); time = 1; sample(); XCTAssertEqual(reads, 1)
        time = 3; sample(); XCTAssertEqual(recorder.values["ios_bytes_read_per_second"], [100])
        diagnostics.state(.paused); time = 30; sample(); XCTAssertEqual(reads, 2)
        diagnostics.state(.playing); sample()
        XCTAssertEqual(recorder.values["ios_bytes_read_per_second"], [100])
        diagnostics.begin(source: source, engine: .avPlayer); diagnostics.state(.playing)
        time = 33; sample(); XCTAssertEqual(recorder.values["ios_bytes_read_per_second"], [100])
        time = 36; sample(0); XCTAssertEqual(reads, 4)
    }

    func testLogFormatterFormatsJSONStringAsKeyValue() {
        let jsonStr = "{\"type\":\"hls\",\"url\":\"https://example.com/live.m3u8\",\"isLive\":true}"
        let formatted = LogFormatter.formatArgument(jsonStr)
        XCTAssertEqual(formatted, "isLive: true, type: hls, url: https://example.com/live.m3u8")

        // Nested JSON
        let nestedJson = "{\"action\":\"switch\",\"data\":{\"codec\":\"h265\",\"rate\":1080}}"
        let formattedNested = LogFormatter.formatArgument(nestedJson)
        XCTAssertEqual(formattedNested, "action: switch, data: [codec: h265, rate: 1080]")

        // Non-JSON string should remain unchanged
        let normalStr = "regular log message"
        XCTAssertEqual(LogFormatter.formatArgument(normalStr), "regular log message")
    }

    func testLogFormatterFormatsDictionaryAndDataAsKeyValue() {
        let dict: [String: Any] = ["alpha": "a", "beta": 2]
        let formattedDict = LogFormatter.formatArgument(dict)
        XCTAssertEqual(formattedDict, "alpha: a, beta: 2")

        let jsonData = try! JSONSerialization.data(withJSONObject: ["key": "val", "num": 1], options: [.sortedKeys])
        let formattedData = LogFormatter.formatArgument(jsonData)
        XCTAssertEqual(formattedData, "key: val, num: 1")
    }

    func testPlayerSourceToKeyValueStringAndJSONCompatibility() {
        let source = PlayerSource(url: "https://example.com/stream.m3u8", type: "hls", isLive: true)
        source.sourceIndex = 1
        source.videoCodec = PlayerSource.CODEC_H264
        source.tag = "main"

        let kvStr = source.toKeyValueString()
        XCTAssertTrue(kvStr.contains("sourceIndex: 1"))
        XCTAssertTrue(kvStr.contains("url: https://example.com/stream.m3u8"))
        XCTAssertTrue(kvStr.contains("type: hls"))
        XCTAssertTrue(kvStr.contains("isLive: true"))
        XCTAssertTrue(kvStr.contains("videoCodec: 2"))
        XCTAssertTrue(kvStr.contains("tag: main"))

        // Ensure toJSONString() remains valid JSON for JSBridge compatibility
        let jsonStr = source.toJSONString()
        let jsonObject = try? JSONSerialization.jsonObject(with: Data(jsonStr.utf8), options: []) as? [String: Any]
        XCTAssertNotNil(jsonObject)
        XCTAssertEqual(jsonObject?["url"] as? String, "https://example.com/stream.m3u8")
        XCTAssertEqual(jsonObject?["type"] as? String, "hls")
    }

    func testInternalLoggerFormatsJSONArguments() {
        let appender = RecordingAppender()
        let logger = InternalLogger(logGroup: "test", level: .info)
        logger.addAppender(appender)

        let source = PlayerSource(url: "https://example.com/live.m3u8", type: "hls", isLive: true)
        logger.logI("source info:", source, fileID: "Test.swift", function: "test()", line: 1)
        XCTAssertEqual(appender.messages.last, "[Test.test():1] source info: " + source.toKeyValueString())

        let jsonPayload = "{\"event\":\"seek\",\"target\":30}"
        logger.logI("payload:", jsonPayload, fileID: "Test.swift", function: "test()", line: 2)
        XCTAssertEqual(appender.messages.last, "[Test.test():2] payload: event: seek, target: 30")

        logger.merged(.info, similarity: 100, format: "data: {}", args: [jsonPayload], fileID: "Test.swift", function: "test()", line: 3)
        XCTAssertEqual(appender.messages.last, "[Test.test():3] data: event: seek, target: 30")
    }
}


extension LoggingTests {
    func testAttachedContextRollsAndNeverUploadsAlone() {
        let uploader = RecordingUploader()
        var policy = LogUploadPolicy(); policy.uploadIntervalSeconds = 600; policy.maxAttachedMessageCount = 2
        let appender = ESUploadAppender(context: LogContext(config: VPlayerConfig()), policy: policy, uploader: uploader)
        defer { appender.destroy() }
        for message in ["oldest", "recent", "latest"] {
            appender.append(level: .info, tag: "", message: message, messageType: .attachedLog)
        }
        appender.flush(); appender.flushIfNeeded()
        XCTAssertTrue(uploader.records.isEmpty)
        for _ in 0..<2 {
            appender.append(level: .warn, tag: "", message: "trigger", messageType: .log)
            appender.flush()
        }
        XCTAssertEqual(uploader.records.count, 2)
        for record in uploader.records {
            let context = record["attachedLogs"] as? String ?? ""
            XCTAssertFalse(context.contains("oldest"))
            XCTAssertTrue(context.contains("recent")); XCTAssertTrue(context.contains("latest"))
        }
        appender.onSourceChanged(srcUrl: "https://new.example/live", srcType: "hls")
        appender.append(level: .info, tag: "", message: "new source", messageType: .log)
        appender.flush()
        XCTAssertEqual(uploader.records.last?["attachedLogs"] as? String, "")
    }

    func testRuntimeStateEventsAndFinish() {
        let output = RecordingAppender()
        Logger.configure { _ in [] }; Logger.addAppender(output)
        let diagnostics = PlaybackDiagnostics(group: "state-test")
        diagnostics.startStateCollection(interval: 0) { ["videoCurrentTime": 12.5, "paused": true] }
        diagnostics.state(.buffering)
        XCTAssertTrue(output.messages.contains { $0.contains("runtime state:") && $0.contains("12.5") && $0.contains("buffering") })
        diagnostics.finish()
        let count = output.messages.count
        diagnostics.collectState(event: "late")
        XCTAssertEqual(output.messages.count, count)
    }
}


extension LoggingTests {
    func testRuntimeStateTimerDoesNotDependOnProgressCallbacks() {
        Logger.configure { _ in [] }
        let diagnostics = PlaybackDiagnostics(group: "timer-test")
        let sampled = expectation(description: "timer sampled while no media progress callbacks")
        var calls = 0
        diagnostics.startStateCollection(interval: 0.1) {
            calls += 1
            if calls == 2 { sampled.fulfill() }
            return ["playState": "buffering"]
        }
        wait(for: [sampled], timeout: 2)
        diagnostics.finish()
    }

    func testSetMutedSnapshotCapturesPostState() {
        let output = RecordingAppender()
        Logger.configure { _ in [] }
        Logger.addAppender(output)
        
        let playerView = MediaPlayerView()
        let player = MultiSourcePlayer(playerView: playerView)
        defer { player.Destroy() }
        player.setSources([PlayerSource(url: "https://example.com/live.m3u8", type: "hls")])
        player.Play()
        
        // 1. 调用真实 MultiSourcePlayer.SetMuted(true)
        player.SetMuted(true)
        
        guard let muteLog = output.messages.last(where: { $0.contains("set_muted: true") && $0.contains("runtime state:") }) else {
            XCTFail("Must capture state snapshot for set_muted: true")
            return
        }
        // 精确断言独立的 muted 字段，避免误匹配 lastEvent 中的 "set_muted: true"
        XCTAssertTrue(muteLog.contains(", muted: true"),
                      "State snapshot for set_muted: true must contain isolated field ', muted: true', got: \(muteLog)")
        XCTAssertFalse(muteLog.contains(", muted: false"),
                       "State snapshot for set_muted: true must NOT contain ', muted: false', got: \(muteLog)")
        
        // 2. 调用真实 MultiSourcePlayer.SetMuted(false)
        player.SetMuted(false)
        
        guard let unmuteLog = output.messages.last(where: { $0.contains("set_muted: false") && $0.contains("runtime state:") }) else {
            XCTFail("Must capture state snapshot for set_muted: false")
            return
        }
        // 精确断言独立的 muted 字段，避免误匹配 lastEvent 中的 "set_muted: false"
        XCTAssertTrue(unmuteLog.contains(", muted: false"),
                      "State snapshot for set_muted: false must contain isolated field ', muted: false', got: \(unmuteLog)")
        XCTAssertFalse(unmuteLog.contains(", muted: true"),
                       "State snapshot for set_muted: false must NOT contain ', muted: true', got: \(unmuteLog)")
    }
}
