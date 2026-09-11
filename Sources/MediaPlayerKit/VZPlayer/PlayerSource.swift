import Foundation

/// 播放源数据模型 (对标 Android vzplayer 的 PlayerSource)
@objc(PlayerSource)
public final class PlayerSource: NSObject, Codable {
    @objc public static let TYPE_HLS = "hls"
    @objc public static let TYPE_FLV = "flv"
    @objc public static let TYPE_RTMP = "rtmp"
    @objc public static let TYPE_AGORA_RTE = "agora-rte"
    
    @objc public static let CODEC_UNKNOWN = 0
    @objc public static let CODEC_H264 = 2
    @objc public static let CODEC_H265 = 4
    
    @objc public var sourceIndex: Int = 0
    @objc public var url: String = ""
    @objc public var type: String = PlayerSource.TYPE_HLS
    @objc public var tag: String = ""
    @objc public var videoCodec: Int = 2 // 2: H.264, 4: H.265
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

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
        init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
        init(_ string: String) { self.stringValue = string; self.intValue = nil }
    }
    
    @objc public override init() {
        super.init()
    }
    
    @objc public init(
        url: String,
        type: String = PlayerSource.TYPE_HLS,
        tag: String = "",
        videoCodec: Int = PlayerSource.CODEC_UNKNOWN,
        sarNum: Int = 1,
        sarDen: Int = 1,
        orderno: Int = 1,
        isLive: Bool = false,
        ext: String = ""
    ) {
        self.url = url
        self.type = type
        self.tag = tag
        if videoCodec != PlayerSource.CODEC_UNKNOWN {
            self.videoCodec = videoCodec
        } else {
            self.videoCodec = PlayerSource.inferCodec(url: url, type: type, tag: tag)
        }
        self.sarNum = sarNum
        self.sarDen = sarDen
        self.orderno = orderno
        self.isLive = isLive
        self.ext = ext
        super.init()
    }

    public required init(from decoder: Decoder) throws {
        super.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let srcVal = try? container.decodeIfPresent(String.self, forKey: .url) {
            self.url = srcVal
        } else {
            let alt = try? decoder.container(keyedBy: DynamicCodingKey.self)
            self.url = (try? alt?.decodeIfPresent(String.self, forKey: DynamicCodingKey("url"))) ?? ""
        }
        
        if let idx = try? container.decodeIfPresent(Int.self, forKey: .sourceIndex) {
            self.sourceIndex = idx
        } else {
            let alt = try? decoder.container(keyedBy: DynamicCodingKey.self)
            self.sourceIndex = (try? alt?.decodeIfPresent(Int.self, forKey: DynamicCodingKey("sourceIndex"))) ?? 0
        }
        
        self.type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? PlayerSource.TYPE_HLS
        self.tag = (try? container.decodeIfPresent(String.self, forKey: .tag)) ?? ""
        self.ext = (try? container.decodeIfPresent(String.self, forKey: .ext)) ?? ""
        self.isLive = (try? container.decodeIfPresent(Bool.self, forKey: .isLive)) ?? false
        
        if let o = try? container.decodeIfPresent(Int.self, forKey: .orderno) {
            self.orderno = o
        } else if let oStr = try? container.decodeIfPresent(String.self, forKey: .orderno), let oInt = Int(oStr) {
            self.orderno = oInt
        } else {
            self.orderno = 1
        }
        
        if let s = try? container.decodeIfPresent(Int.self, forKey: .sarNum) {
            self.sarNum = s
        } else if let sStr = try? container.decodeIfPresent(String.self, forKey: .sarNum), let sInt = Int(sStr) {
            self.sarNum = sInt
        } else {
            self.sarNum = 1
        }
        
        if let s = try? container.decodeIfPresent(Int.self, forKey: .sarDen) {
            self.sarDen = s
        } else if let sStr = try? container.decodeIfPresent(String.self, forKey: .sarDen), let sInt = Int(sStr) {
            self.sarDen = sInt
        } else {
            self.sarDen = 1
        }
        
        var explicitCodec: Int? = nil
        if let c = try? container.decodeIfPresent(Int.self, forKey: .videoCodec) {
            explicitCodec = c
        } else if let cStr = try? container.decodeIfPresent(String.self, forKey: .videoCodec) {
            explicitCodec = PlayerSource.parseCodec(cStr)
        } else {
            let alt = try? decoder.container(keyedBy: DynamicCodingKey.self)
            if let c = try? alt?.decodeIfPresent(Int.self, forKey: DynamicCodingKey("codec")) {
                explicitCodec = c
            } else if let cStr = try? alt?.decodeIfPresent(String.self, forKey: DynamicCodingKey("codec")) {
                explicitCodec = PlayerSource.parseCodec(cStr)
            } else if let vc = try? alt?.decodeIfPresent(Int.self, forKey: DynamicCodingKey("video_codec")) {
                explicitCodec = vc
            } else if let vcStr = try? alt?.decodeIfPresent(String.self, forKey: DynamicCodingKey("video_codec")) {
                explicitCodec = PlayerSource.parseCodec(vcStr)
            }
        }
        
        if let codec = explicitCodec {
            self.videoCodec = codec
        } else {
            self.videoCodec = PlayerSource.inferCodec(url: self.url, type: self.type, tag: self.tag)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceIndex, forKey: .sourceIndex)
        try container.encode(url, forKey: .url)
        try container.encode(type, forKey: .type)
        try container.encode(tag, forKey: .tag)
        try container.encode(videoCodec, forKey: .videoCodec)
        try container.encode(sarNum, forKey: .sarNum)
        try container.encode(sarDen, forKey: .sarDen)
        try container.encode(orderno, forKey: .orderno)
        try container.encode(isLive, forKey: .isLive)
        try container.encode(ext, forKey: .ext)
    }
    
    public func toDictionary() -> [String: Any] {
        return [
            "index": sourceIndex,
            "sourceIndex": sourceIndex,
            "src": url,
            "url": url,
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
        // H5 的旧字段与 Android 标准字段使用同一份输出。
        guard let data = try? JSONSerialization.data(withJSONObject: toDictionary()),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
    
    /// 输出为键值对形式（用于日志打印）
    public func toKeyValueString() -> String {
        let dict = toDictionary()
        let preferredOrder = ["sourceIndex", "url", "type", "isLive", "videoCodec", "sar_num", "sar_den", "orderno", "tag", "ext"]
        var parts: [String] = []
        for key in preferredOrder {
            if let val = dict[key] {
                parts.append("\(key): \(LogFormatter.formatValue(val))")
            }
        }
        for key in dict.keys.sorted() where !preferredOrder.contains(key) {
            parts.append("\(key): \(LogFormatter.formatValue(dict[key]!))")
        }
        return parts.joined(separator: ", ")
    }
    
    public static func parseCodec(_ raw: Any?) -> Int? {
        if let intVal = raw as? Int {
            return intVal
        }
        if let numVal = raw as? NSNumber {
            return numVal.intValue
        }
        if let strVal = raw as? String {
            let lower = strVal.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if lower == "4" || lower == "h265" || lower == "hevc" || lower.contains("265") || lower.contains("hevc") {
                return CODEC_H265
            }
            if lower == "2" || lower == "h264" || lower == "avc" || lower.contains("264") || lower.contains("avc") {
                return CODEC_H264
            }
            return Int(lower)
        }
        return nil
    }

    public static func inferCodec(url: String, type: String, tag: String) -> Int {
        let typeLower = type.lowercased()
        let tagLower = tag.lowercased()
        
        // 1. Check type
        if typeLower.contains("265") || typeLower.contains("hevc") {
            return CODEC_H265
        }
        
        // 2. Check tag: exact match or clear prefix/suffix
        if tagLower == "hevc" || tagLower == "h265" || tagLower.hasPrefix("hevc") || tagLower.hasPrefix("h265") ||
           tagLower.contains("-hevc") || tagLower.contains("_hevc") || tagLower.contains("-265") || tagLower.contains("_265") {
            return CODEC_H265
        }
        
        // 3. Check URL path (strictly EXCLUDE query parameters like ?token=hevc_xxx)
        let pathLower: String
        if let parsedURL = URL(string: url) {
            pathLower = parsedURL.path.lowercased()
        } else {
            pathLower = url.components(separatedBy: "?").first?.lowercased() ?? ""
        }
        if pathLower.contains("265") || pathLower.contains("hevc") {
            return CODEC_H265
        }
        
        return CODEC_H264
    }

    public static func fromDictionary(_ dict: [String: Any]) -> PlayerSource {
        let source = PlayerSource()
        source.sourceIndex = dict["index"] as? Int ?? dict["sourceIndex"] as? Int ?? 0
        source.url = dict["src"] as? String ?? dict["url"] as? String ?? ""
        source.type = dict["type"] as? String ?? TYPE_HLS
        source.tag = dict["tag"] as? String ?? ""
        
        let rawCodec = dict["videoCodec"] ?? dict["codec"] ?? dict["video_codec"]
        if let explicit = parseCodec(rawCodec) {
            source.videoCodec = explicit
        } else {
            source.videoCodec = inferCodec(url: source.url, type: source.type, tag: source.tag)
        }

        source.sarNum = dict["sar_num"] as? Int ?? 1
        source.sarDen = dict["sar_den"] as? Int ?? 1
        source.orderno = dict["orderno"] as? Int ?? 1
        source.ext = dict["ext"] as? String ?? ""
        source.isLive = dict["isLive"] as? Bool ?? false
        return source
    }
}

