import XCTest
@testable import MediaPlayerKit

final class CodecFieldTests: XCTestCase {
    func testOnlyVideoCodecControlsParsing() throws {
        let cases: [(Any?, Int)] = [(nil, 0), (NSNull(), 0), (4, 4), ("4", 4),
            (" HEVC ", 4), ("H.265", 4), (2, 2), ("avc", 2), (0, 0), (true, 0),
            (4.5, 0), (4.0, 4), ("not-hevc", 0), ("bad", 0)]
        for (value, expected) in cases {
            var dict: [String: Any] = ["src": "https://example.com/hevc.m3u8?codec=265",
                "type": "hls_hevc", "tag": "hevc", "codec": "hevc", "video_codec": 4]
            dict["videoCodec"] = value
            let parsed = PlayerSource.fromDictionary(dict)
            let decoded = try JSONDecoder().decode(PlayerSource.self, from: JSONSerialization.data(withJSONObject: dict))
            XCTAssertEqual(parsed.videoCodec, expected, "dictionary: \(String(describing: value))")
            XCTAssertEqual(decoded.videoCodec, expected, "Codable: \(String(describing: value))")
        }
    }
    func testInitializersRemainUnknownWithoutCodec() {
        let source = PlayerSource()
        source.url = "https://example.com/hevc.m3u8"
        source.tag = "h265"
        XCTAssertEqual(source.videoCodec, PlayerSource.CODEC_UNKNOWN)
        XCTAssertEqual(PlayerSource(url: source.url, type: "hls_hevc", tag: "hevc").videoCodec, PlayerSource.CODEC_UNKNOWN)
        XCTAssertEqual(PlayerSource(url: source.url, videoCodec: 2).videoCodec, 2)
    }
    func testNativeIntegerFastPathDoesNotAcceptBoxedBooleans() {
        XCTAssertEqual(PlayerSource.parseCodec(Int.max), Int.max)
        XCTAssertEqual(PlayerSource.parseCodec(4), 4)
        XCTAssertEqual(PlayerSource.parseCodec(NSNumber(value: 4)), 4)
        XCTAssertNil(PlayerSource.parseCodec(NSNumber(value: true)))
        XCTAssertNil(PlayerSource.parseCodec(NSNumber(value: false)))
    }
    func testCodecRoundTrip() throws {
        for code in [0, 2, 4, 7] {
            let source = PlayerSource(url: "https://example.com/hevc.m3u8", videoCodec: code)
            let decoded = try JSONDecoder().decode(PlayerSource.self, from: JSONEncoder().encode(source))
            XCTAssertEqual(decoded.videoCodec, code)
        }
    }
}
