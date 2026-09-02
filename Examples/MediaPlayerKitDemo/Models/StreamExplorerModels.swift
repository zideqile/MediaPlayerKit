import Foundation

// MARK: - 节点流列表响应
public struct NodeStreamListResponse: Codable {
    public let count: Int?
    public let streams: [NodeStreamInfo]?
    
    enum CodingKeys: String, CodingKey {
        case count, streams
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intVal = try? container.decodeIfPresent(Int.self, forKey: .count) {
            self.count = intVal
        } else if let strVal = try? container.decodeIfPresent(String.self, forKey: .count) {
            self.count = Int(strVal)
        } else {
            self.count = nil
        }
        self.streams = try? container.decodeIfPresent([NodeStreamInfo].self, forKey: .streams)
    }
}

public struct NodeStreamInfo: Codable, Identifiable {
    public var id: String { streamid }
    public let streamid: String
    public let liveid: String?
    public let time: Double?
    public let vfps: Double?
    public let afps: Double?
    public let vbitrate: Double?
    public let abitrate: Double?
    public let width: Int?
    public let height: Int?
    public let urlquery: String?
    public let metadata: String?
    public let clientipdata: ClientIPData?
    
    enum CodingKeys: String, CodingKey {
        case streamid, liveid, time, vfps, afps, vbitrate, abitrate, width, height, urlquery, metadata, clientipdata
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.streamid = try container.decodeIfPresent(String.self, forKey: .streamid) ?? ""
        
        if let str = try? container.decodeIfPresent(String.self, forKey: .liveid) {
            self.liveid = str
        } else if let intVal = try? container.decodeIfPresent(Int.self, forKey: .liveid) {
            self.liveid = String(intVal)
        } else {
            self.liveid = nil
        }
        
        self.time = Self.decodeDouble(container: container, key: .time)
        self.vfps = Self.decodeDouble(container: container, key: .vfps)
        self.afps = Self.decodeDouble(container: container, key: .afps)
        self.vbitrate = Self.decodeDouble(container: container, key: .vbitrate)
        self.abitrate = Self.decodeDouble(container: container, key: .abitrate)
        self.width = Self.decodeInt(container: container, key: .width)
        self.height = Self.decodeInt(container: container, key: .height)
        
        self.urlquery = try? container.decodeIfPresent(String.self, forKey: .urlquery)
        self.metadata = try? container.decodeIfPresent(String.self, forKey: .metadata)
        self.clientipdata = try? container.decodeIfPresent(ClientIPData.self, forKey: .clientipdata)
    }
    
    private static func decodeDouble(container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Double? {
        if let val = try? container.decodeIfPresent(Double.self, forKey: key) { return val }
        if let val = try? container.decodeIfPresent(Int.self, forKey: key) { return Double(val) }
        if let str = try? container.decodeIfPresent(String.self, forKey: key) { return Double(str) }
        return nil
    }
    
    private static func decodeInt(container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int? {
        if let val = try? container.decodeIfPresent(Int.self, forKey: key) { return val }
        if let val = try? container.decodeIfPresent(Double.self, forKey: key) { return Int(val) }
        if let str = try? container.decodeIfPresent(String.self, forKey: key) { return Int(str) }
        return nil
    }
    
    public var resolutionText: String {
        guard let w = width, let h = height, w > 0, h > 0 else { return "" }
        return "\(w)x\(h)"
    }
    
    public var fpsText: String {
        guard let vf = vfps, let af = afps, vf > 0 || af > 0 else { return "" }
        return String(format: "V:%.0f/A:%.0f fps", vf, af)
    }
    
    public var bitrateText: String {
        let v = vbitrate ?? 0
        let a = abitrate ?? 0
        let totalKbps = Int((v + a) * 8 / 1000)
        guard totalKbps > 0 else { return "" }
        if totalKbps > 1000 {
            return String(format: "%.2f Mbps", Double(totalKbps) / 1000.0)
        }
        return "\(totalKbps) Kbps"
    }
    
    public var locationText: String {
        guard let ipData = clientipdata else { return "" }
        let prov = ipData.province ?? ""
        let city = ipData.city ?? ""
        let isp = ipData.isp ?? ""
        return "\(prov)\(city) \(isp)".trimmingCharacters(in: .whitespaces)
    }
}

public struct ClientIPData: Codable {
    public let ip: String?
    public let country: String?
    public let province: String?
    public let city: String?
    public let isp: String?
}

// MARK: - 播放地址源列表响应
public struct PlayerSourcesResponse: Codable {
    public let streamId: String?
    public let playerSources: PlayerSourcesContainer?
}

public struct PlayerSourcesContainer: Codable {
    public let h5playerSources: [PlayerSourceItem]?
    public let miniplayerSources: [PlayerSourceItem]?
    public let obplayerSources: [PlayerSourceItem]?
    
    public var allSources: [PlayerSourceItem] {
        var list: [PlayerSourceItem] = []
        if let mini = miniplayerSources { list.append(contentsOf: mini) }
        if let h5 = h5playerSources { list.append(contentsOf: h5) }
        if let ob = obplayerSources { list.append(contentsOf: ob) }
        return list
    }
}

public struct PlayerSourceItem: Codable, Identifiable {
    public var id: String { src }
    public let type: String
    public let src: String
    public let tag: String?
    public let videoCodec: Int?
    public let vendor: String?
    public let orderno: Int?
    public let sar_num: Int?
    public let sar_den: Int?
    
    enum CodingKeys: String, CodingKey {
        case type, src, tag, videoCodec, vendor, orderno, sar_num, sar_den
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        self.src = try container.decodeIfPresent(String.self, forKey: .src) ?? ""
        self.tag = try container.decodeIfPresent(String.self, forKey: .tag)
        self.vendor = try container.decodeIfPresent(String.self, forKey: .vendor)
        
        // 兼容 videoCodec 可以为 Int 或 String
        if let intVal = try? container.decodeIfPresent(Int.self, forKey: .videoCodec) {
            self.videoCodec = intVal
        } else if let strVal = try? container.decodeIfPresent(String.self, forKey: .videoCodec) {
            self.videoCodec = Int(strVal)
        } else {
            self.videoCodec = nil
        }
        
        // 兼容 orderno 可以为 Int 或 String
        if let intVal = try? container.decodeIfPresent(Int.self, forKey: .orderno) {
            self.orderno = intVal
        } else if let strVal = try? container.decodeIfPresent(String.self, forKey: .orderno) {
            self.orderno = Int(strVal)
        } else {
            self.orderno = nil
        }
        
        // 兼容 sar_num 可以为 Int 或 String
        if let intVal = try? container.decodeIfPresent(Int.self, forKey: .sar_num) {
            self.sar_num = intVal
        } else if let strVal = try? container.decodeIfPresent(String.self, forKey: .sar_num) {
            self.sar_num = Int(strVal)
        } else {
            self.sar_num = nil
        }
        
        // 兼容 sar_den 可以为 Int 或 String
        if let intVal = try? container.decodeIfPresent(Int.self, forKey: .sar_den) {
            self.sar_den = intVal
        } else if let strVal = try? container.decodeIfPresent(String.self, forKey: .sar_den) {
            self.sar_den = Int(strVal)
        } else {
            self.sar_den = nil
        }
    }
    
    public var codecText: String {
        switch videoCodec {
        case 4: return "H.265"
        case 2, 7: return "H.264"
        case .some(let c): return "Codec:\(c)"
        case .none: return ""
        }
    }
}
