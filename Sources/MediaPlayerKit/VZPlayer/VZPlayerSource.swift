import Foundation

/// 播放源数据模型 (对标 Android vzplayer 的 PlayerSource)
@objc public final class VZPlayerSource: NSObject, Codable {
    @objc public static let TYPE_HLS = "hls"
    @objc public static let TYPE_FLV = "flv"
    @objc public static let TYPE_RTMP = "rtmp"
    @objc public static let TYPE_AGORA_RTE = "rte"
    
    @objc public var sourceIndex: Int = 0
    @objc public var url: String = ""
    @objc public var type: String = VZPlayerSource.TYPE_HLS
    @objc public var tag: String = ""
    @objc public var videoCodec: Int = 1 // 1: H.264, 2: H.265
    @objc public var sarNum: Int = 1
    @objc public var sarDen: Int = 1
    @objc public var orderno: Int = 1
    @objc public var isLive: Bool = false
    @objc public var ext: String = ""
    
    enum CodingKeys: String, CodingKey {
        case sourceIndex = "index"
        case url = "src"
        case type
        case tag
        case videoCodec
        case sarNum = "sar_num"
        case sarDen = "sar_den"
        case orderno
        case isLive
        case ext
    }
    
    @objc public override init() {
        super.init()
    }
    
    @objc public init(
        url: String,
        type: String = VZPlayerSource.TYPE_HLS,
        tag: String = "",
        videoCodec: Int = 1,
        sarNum: Int = 1,
        sarDen: Int = 1,
        orderno: Int = 1,
        isLive: Bool = false,
        ext: String = ""
    ) {
        self.url = url
        self.type = type
        self.tag = tag
        self.videoCodec = videoCodec
        self.sarNum = sarNum
        self.sarDen = sarDen
        self.orderno = orderno
        self.isLive = isLive
        self.ext = ext
        super.init()
    }
    
    public func toDictionary() -> [String: Any] {
        return [
            "index": sourceIndex,
            "src": url,
            "type": type,
            "tag": tag,
            "videoCodec": videoCodec,
            "sar_num": sarNum,
            "sar_den": sarDen,
            "orderno": orderno,
            "ext": ext,
            "isLive": isLive
        ]
    }
    
    public func toJSONString() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
    
    public static func fromDictionary(_ dict: [String: Any]) -> VZPlayerSource {
        let source = VZPlayerSource()
        source.sourceIndex = dict["index"] as? Int ?? 0
        source.url = dict["src"] as? String ?? dict["url"] as? String ?? ""
        source.type = dict["type"] as? String ?? TYPE_HLS
        source.tag = dict["tag"] as? String ?? ""
        source.videoCodec = dict["videoCodec"] as? Int ?? 1
        source.sarNum = dict["sar_num"] as? Int ?? 1
        source.sarDen = dict["sar_den"] as? Int ?? 1
        source.orderno = dict["orderno"] as? Int ?? 1
        source.ext = dict["ext"] as? String ?? ""
        source.isLive = dict["isLive"] as? Bool ?? false
        return source
    }
}
