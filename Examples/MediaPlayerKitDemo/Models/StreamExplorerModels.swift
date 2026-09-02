import Foundation

// MARK: - 节点流列表响应
public struct NodeStreamListResponse: Codable {
    public let count: Int?
    public let streams: [NodeStreamInfo]?
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
    
    public var codecText: String {
        switch videoCodec {
        case 4: return "H.265"
        case 2, 7: return "H.264"
        case .some(let c): return "Codec:\(c)"
        case .none: return ""
        }
    }
}
