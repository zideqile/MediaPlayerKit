import XCTest
@testable import MediaPlayerKit

final class PlaybackRecoveryTests: XCTestCase {
    func testSourceErrorsSkipEngineFallback() {
        for category in [PlaybackErrorCategory.sourceNotFound, .invalidSource] {
            XCTAssertEqual(PlaybackRecoveryPolicy.action(for: category, hasNextEngine: true, hasNextSource: true), .nextSource)
            XCTAssertEqual(PlaybackRecoveryPolicy.action(for: category, hasNextEngine: true, hasNextSource: false), .stop)
        }
    }
    func testOtherErrorsExhaustEnginesBeforeSources() {
        for category in [PlaybackErrorCategory.unknown, .network, .timeout, .authorization, .decoding] {
            XCTAssertEqual(PlaybackRecoveryPolicy.action(for: category, hasNextEngine: true, hasNextSource: true), .nextEngine)
            XCTAssertEqual(PlaybackRecoveryPolicy.action(for: category, hasNextEngine: false, hasNextSource: true), .nextSource)
            XCTAssertEqual(PlaybackRecoveryPolicy.action(for: category, hasNextEngine: false, hasNextSource: false), .stop)
        }
        XCTAssertEqual(PlaybackRecoveryPolicy.action(for: .cancelled, hasNextEngine: true, hasNextSource: true), .stop)
    }
    func testStructuredHTTPAndUnderlyingErrors() {
        for (status, category) in [(404, PlaybackErrorCategory.sourceNotFound), (410, .sourceNotFound),
                                   (401, .authorization), (403, .authorization), (504, .timeout), (503, .network)] {
            let inner = NSError(domain: "engine", code: -1, userInfo: [PlaybackErrorClassifier.httpStatusKey: status])
            let outer = NSError(domain: "wrapper", code: -1, userInfo: [NSUnderlyingErrorKey: inner])
            XCTAssertEqual(PlaybackErrorClassifier.classify(outer), category)
        }
    }
    func testURLDomainMappingAndUnrelatedCodes() {
        for (code, category) in [(NSURLErrorTimedOut, PlaybackErrorCategory.timeout),
            (NSURLErrorNotConnectedToInternet, .network), (NSURLErrorCancelled, .cancelled),
            (NSURLErrorBadURL, .invalidSource), (NSURLErrorUserAuthenticationRequired, .authorization)] {
            XCTAssertEqual(PlaybackErrorClassifier.classify(NSError(domain: NSURLErrorDomain, code: code)), category)
            XCTAssertEqual(PlaybackErrorClassifier.classify(NSError(domain: "other", code: code)), .unknown)
        }
        let message = "Decoder not found for https://example.com/404/live.m3u8"
        XCTAssertEqual(PlaybackErrorClassifier.classify(NSError(domain: "other", code: 404,
            userInfo: [NSLocalizedDescriptionKey: message])), .unknown)
    }
    func testDeepUnderlyingChainIsBounded() {
        var error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        for _ in 0..<30 { error = NSError(domain: "wrapper", code: -1, userInfo: [NSUnderlyingErrorKey: error]) }
        XCTAssertEqual(PlaybackErrorClassifier.classify(error), .unknown)
    }
}

#if canImport(AVFoundation)
import AVFoundation
import KSPlayer

private final class RecoveryRecorder: NSObject, PlayerEventListener {
    var events: [String] = []
    var failures: [PlaybackAttemptFailure] = []
    var completed: (() -> Void)?
    var attempt: (() -> Void)?
    func onStateChanged(state: PlayerState) { events.append("state:\(state)") }
    func onFirstFrameRendered() {}
    func onTimeUpdate(currentTime: Int64, totalDuration: Int64) {}
    func onError(code: Int, errMsg: String) { events.append("error"); completed?() }
    func onPlayToEnd() {}
    func onSourceSwitched(source: PlayerSource) {}
    func onWarnMessage(msg: String) {}
    func onPlayAttemptFailed(_ failure: PlaybackAttemptFailure) {
        failures.append(failure); events.append("attempt"); attempt?()
    }
    func onRecoveryStarted(_ failure: PlaybackAttemptFailure) { events.append("recovering") }
}

extension PlaybackRecoveryTests {
    func testPlatformDecoderAndFFmpegHTTPClassification() {
        let av = NSError(domain: AVFoundationErrorDomain, code: AVFoundation.AVError.Code.decodeFailed.rawValue)
        XCTAssertEqual(PlaybackErrorAdapters.classify(av), .decoding)
        let me = NSError(domain: KSPlayerErrorDomain, code: KSPlayerErrorCode.formatOpenInput.rawValue,
                         userInfo: [NSUnderlyingErrorKey: KSPlayer.AVError.httpNotFound])
        XCTAssertEqual(PlaybackErrorAdapters.classify(me), .sourceNotFound)
    }
    func testInvalidSourcesRecoverThenReportExactlyOneFinalError() {
        let done = expectation(description: "final error")
        DispatchQueue.main.async {
            let player = MultiSourcePlayer(playerView: MediaPlayerView())
            let recorder = RecoveryRecorder()
            recorder.completed = {
                XCTAssertEqual(recorder.failures.map { $0.sourceIndex }, [0, 1])
                XCTAssertEqual(recorder.events, ["attempt", "recovering", "attempt", "state:error", "error"])
                XCTAssertEqual(player.failureHistory.count, 2)
                player.Destroy()
                recorder.completed = nil
                done.fulfill()
            }
            player.AddEventListener(recorder)
            // No engine or network request is created for these invalid URLs.
            XCTAssertTrue(player.Play([PlayerSource(url: ""), PlayerSource(url: "relative/path")]))
        }
        wait(for: [done], timeout: 2)
    }
    func testDestroyFromAttemptCallbackCancelsRecovery() {
        let done = expectation(description: "queued recovery cancelled")
        DispatchQueue.main.async {
            let player = MultiSourcePlayer(playerView: MediaPlayerView())
            let recorder = RecoveryRecorder()
            recorder.attempt = { player.Destroy() }
            player.AddEventListener(recorder)
            _ = player.Play([PlayerSource(url: ""), PlayerSource(url: "relative")])
            DispatchQueue.main.async {
                XCTAssertEqual(recorder.events, ["attempt"])
                XCTAssertFalse(player.Play([]))
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 2)
    }
}

private final class RecoveryH5Recorder: NSObject, H5EventListener {
    var events: [String] = []
    var errorCount = 0
    func onEvent(_ eventName: String) { events.append(eventName) }
    func onError(_ code: Int, errMsg: String) { errorCount += 1 }
    func onTimeUpdate(_ currentTime: Int64) {}
}
extension PlaybackRecoveryTests {
    func testH5MapsOnlyTerminalFailureToPlayerWARN() {
        let done = expectation(description: "native final error and H5 warning")
        DispatchQueue.main.async {
            let player = H5Player(playerView: MediaPlayerView())
            let h5 = RecoveryH5Recorder()
            let native = RecoveryRecorder()
            player.SetOnH5EventListener(h5)
            player.AddEventListener(native)
            native.completed = {
                XCTAssertEqual(h5.events, ["recovering", "PlayerWARN"])
                XCTAssertEqual(h5.errorCount, 0)
                XCTAssertEqual(native.events.filter { $0 == "error" }.count, 1)
                player.destroy()
                native.completed = nil
                done.fulfill()
            }
            player.onWarnMessage(msg: "intermediate diagnostic")
            XCTAssertTrue(h5.events.isEmpty)
            player.setSources([PlayerSource(url: ""), PlayerSource(url: "relative")])
            player.play()
        }
        wait(for: [done], timeout: 2)
    }
}
#endif
