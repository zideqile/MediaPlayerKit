import Foundation
import Combine

extension String {
    /// 对 Query 参数进行标准 URI Percent-Encoding
    public func urlQueryComponentEncoded() -> String {
        let decoded = self.removingPercentEncoding ?? self
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return decoded.addingPercentEncoding(withAllowedCharacters: allowed) ?? decoded
    }
}

public final class StreamAPIService: ObservableObject {
    public static let shared = StreamAPIService()
    
    private let kApiDomainKey = "StreamAPIService_ApiDomain_V3"
    private let kSignKey = "StreamAPIService_Sign_V3"
    private let kNodeItemsKey = "StreamAPIService_NodeItems_V3"
    private let kActiveNodeDomainKey = "StreamAPIService_ActiveNodeDomain_V3"
    
    @Published public var apiDomain: String {
        didSet {
            UserDefaults.standard.set(apiDomain, forKey: kApiDomainKey)
            triggerAutoFetchIfComplete()
        }
    }
    
    @Published public var sign: String {
        didSet {
            UserDefaults.standard.set(sign, forKey: kSignKey)
            triggerAutoFetchIfComplete()
        }
    }
    
    @Published public var nodeItems: [NodeConfigItem] {
        didSet {
            if let data = try? JSONEncoder().encode(nodeItems) {
                UserDefaults.standard.set(data, forKey: kNodeItemsKey)
            }
        }
    }
    
    @Published public var activeNodeDomain: String {
        didSet {
            UserDefaults.standard.set(activeNodeDomain, forKey: kActiveNodeDomainKey)
            triggerAutoFetchIfComplete()
        }
    }
    
    @Published public var streamList: [NodeStreamInfo] = []
    @Published public var isLoadingStreams: Bool = false
    @Published public var streamListError: String? = nil
    
    @Published public var selectedStreamId: String? = nil
    @Published public var playerSources: PlayerSourcesContainer? = nil
    @Published public var isLoadingSources: Bool = false
    @Published public var sourcesError: String? = nil
    
    // 播放源快速内存缓存 [StreamID: PlayerSourcesContainer]
    @Published public var sourcesCache: [String: PlayerSourcesContainer] = [:]
    
    public init() {
        self.apiDomain = UserDefaults.standard.string(forKey: kApiDomainKey) ?? "vadmin.weizan.cn"
        self.sign = UserDefaults.standard.string(forKey: kSignKey) ?? "!@#$VZanLIVE"
        
        // 读取节点列表
        let loadedItems: [NodeConfigItem]
        if let data = UserDefaults.standard.data(forKey: kNodeItemsKey),
           let items = try? JSONDecoder().decode([NodeConfigItem].self, from: data) {
            loadedItems = items
        } else {
            loadedItems = []
        }
        self.nodeItems = loadedItems
        
        let savedActive = UserDefaults.standard.string(forKey: kActiveNodeDomainKey) ?? ""
        if !savedActive.isEmpty {
            self.activeNodeDomain = savedActive
        } else if let first = loadedItems.first {
            self.activeNodeDomain = first.domain
        } else {
            self.activeNodeDomain = ""
        }
    }
    
    public var hasCompleteConfig: Bool {
        let a = apiDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = activeNodeDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = sign.trimmingCharacters(in: .whitespacesAndNewlines)
        return !a.isEmpty && !n.isEmpty && !s.isEmpty
    }
    
    public var activeNodeItem: NodeConfigItem? {
        return nodeItems.first { $0.domain == activeNodeDomain }
    }
    
    // MARK: - 节点管理方法
    public func addNode(domain: String, remark: String) {
        let cleanD = cleanRawDomain(domain)
        guard !cleanD.isEmpty else { return }
        
        let newItem = NodeConfigItem(domain: cleanD, remark: remark.trimmingCharacters(in: .whitespacesAndNewlines))
        // 避免重复添加完全相同域名的项
        if let idx = nodeItems.firstIndex(where: { $0.domain == cleanD }) {
            nodeItems[idx] = newItem
        } else {
            nodeItems.append(newItem)
        }
        
        if activeNodeDomain.isEmpty {
            activeNodeDomain = cleanD
        }
    }
    
    public func deleteNode(at offsets: IndexSet) {
        nodeItems.remove(atOffsets: offsets)
        if !nodeItems.contains(where: { $0.domain == activeNodeDomain }) {
            activeNodeDomain = nodeItems.first?.domain ?? ""
        }
    }
    
    public func setActiveNode(domain: String) {
        self.activeNodeDomain = domain
        // 切换节点时清空旧节点的流缓存并重新拉流
        self.streamList = []
        self.selectedStreamId = nil
        self.playerSources = nil
        self.sourcesCache.removeAll()
        fetchStreamList()
    }
    
    public func triggerAutoFetchIfComplete() {
        if hasCompleteConfig {
            fetchStreamList()
        }
    }
    
    private func normalizeUrlPrefix(_ input: String, defaultScheme: String = "http") -> String {
        var str = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !str.hasPrefix("http://") && !str.hasPrefix("https://") {
            str = "\(defaultScheme)://\(str)"
        }
        if str.hasSuffix("/") {
            str = String(str.dropLast())
        }
        return str
    }
    
    public func cleanRawDomain(_ domain: String) -> String {
        var d = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.hasPrefix("http://") { d = String(d.dropFirst(7)) }
        if d.hasPrefix("https://") { d = String(d.dropFirst(8)) }
        if d.hasSuffix("/") { d = String(d.dropLast(1)) }
        return d
    }
    
    // MARK: - 1. 获取流列表 (基于当前选中的节点 activeNodeDomain)
    public func fetchStreamList(completion: (([NodeStreamInfo]) -> Void)? = nil) {
        guard hasCompleteConfig else {
            self.streamListError = "请在「配置」页填写接口域名、选择节点并配置 Sign"
            completion?([])
            return
        }
        
        let nodeBase = normalizeUrlPrefix(activeNodeDomain, defaultScheme: "http")
        let cAdmin = cleanRawDomain(apiDomain)
        let cNode = cleanRawDomain(activeNodeDomain)
        let encodedSign = sign.urlQueryComponentEncoded()
        
        let candidateUrls: [String] = [
            "\(nodeBase)/manager/streamclientipdata?sign=\(encodedSign)",
            "https://\(cAdmin)/\(cNode)/manager/streamclientipdata?sign=\(encodedSign)",
            "http://\(cNode)/manager/streamclientipdata?sign=\(encodedSign)"
        ]
        
        self.isLoadingStreams = true
        self.streamListError = nil
        
        tryFetchCandidates(urls: candidateUrls, index: 0) { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingStreams = false
                
                if let err = error {
                    self.streamListError = "获取流列表失败: \(err.localizedDescription)"
                    completion?([])
                    return
                }
                guard let data = data else {
                    self.streamListError = "返回数据为空"
                    completion?([])
                    return
                }
                
                do {
                    let resp = try JSONDecoder().decode(NodeStreamListResponse.self, from: data)
                    let rawList = resp.streams ?? []
                    // 严格过滤掉带 @ 字符的内部流
                    let list = rawList.filter { !$0.streamid.contains("@") }
                    self.streamList = list
                    if list.isEmpty {
                        self.streamListError = "当前节点暂无活跃推流 (已过滤内部流)"
                    } else {
                        self.streamListError = nil
                    }
                    completion?(list)
                } catch {
                    self.streamListError = "解析流列表失败: \(error.localizedDescription)"
                    completion?([])
                }
            }
        }
    }
    
    private func tryFetchCandidates(urls: [String], index: Int, completion: @escaping (Data?, Error?) -> Void) {
        guard index < urls.count else {
            completion(nil, NSError(domain: "StreamAPIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "所有节点候选连接均失败"]))
            return
        }
        guard let url = URL(string: urls[index]) else {
            tryFetchCandidates(urls: urls, index: index + 1, completion: completion)
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 6.0
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode), let data = data, data.count > 0 {
                completion(data, nil)
            } else {
                self?.tryFetchCandidates(urls: urls, index: index + 1, completion: completion)
            }
        }
        task.resume()
    }
    
    // MARK: - 2. 获取播放地址列表
    public func fetchPlayerSources(for streamId: String, completion: ((PlayerSourcesContainer?) -> Void)? = nil) {
        let trimmedId = streamId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else {
            completion?(nil)
            return
        }
        
        // 优先检查内存缓存
        if let cached = sourcesCache[trimmedId] {
            self.selectedStreamId = trimmedId
            self.playerSources = cached
            self.sourcesError = nil
            completion?(cached)
            return
        }
        
        let apiBase = normalizeUrlPrefix(apiDomain, defaultScheme: "https")
        let encodedStreamId = trimmedId.urlQueryComponentEncoded()
        guard let url = URL(string: "\(apiBase)/toolsapi/v1/player-sources/?streamId=\(encodedStreamId)") else {
            self.sourcesError = "播放地址 API 格式不正确"
            completion?(nil)
            return
        }
        
        self.selectedStreamId = trimmedId
        self.isLoadingSources = true
        self.sourcesError = nil
        self.playerSources = nil
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingSources = false
                
                if let err = error {
                    self.sourcesError = "获取播放地址失败: \(err.localizedDescription)"
                    completion?(nil)
                    return
                }
                guard let data = data else {
                    self.sourcesError = "播放地址返回为空"
                    completion?(nil)
                    return
                }
                
                do {
                    let resp = try JSONDecoder().decode(PlayerSourcesResponse.self, from: data)
                    if let container = resp.playerSources {
                        self.playerSources = container
                        self.sourcesCache[trimmedId] = container
                        if container.allSources.isEmpty {
                            self.sourcesError = "未查询到可用播放地址"
                        }
                        completion?(container)
                    } else {
                        self.sourcesError = "未查询到可用播放地址"
                        completion?(nil)
                    }
                } catch {
                    self.sourcesError = "解析播放地址失败: \(error.localizedDescription)"
                    completion?(nil)
                }
            }
        }.resume()
    }
}
