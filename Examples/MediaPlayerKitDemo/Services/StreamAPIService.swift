import Foundation
import Combine

extension String {
    /// 对 Query 参数进行标准 URI Percent-Encoding
    /// 确保 ! @ # $ & = + / 等特殊字符被正确转义，避免 # 被当做 URL Fragment 截断
    public func urlQueryComponentEncoded() -> String {
        let decoded = self.removingPercentEncoding ?? self
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return decoded.addingPercentEncoding(withAllowedCharacters: allowed) ?? decoded
    }
}

public final class StreamAPIService: ObservableObject {
    public static let shared = StreamAPIService()
    
    private let kApiDomainKey = "StreamAPIService_ApiDomain_V2"
    private let kNodeDomainKey = "StreamAPIService_NodeDomain_V2"
    private let kSignKey = "StreamAPIService_Sign_V2"
    
    @Published public var apiDomain: String {
        didSet {
            UserDefaults.standard.set(apiDomain, forKey: kApiDomainKey)
            triggerAutoFetchIfComplete()
        }
    }
    @Published public var nodeDomain: String {
        didSet {
            UserDefaults.standard.set(nodeDomain, forKey: kNodeDomainKey)
            triggerAutoFetchIfComplete()
        }
    }
    @Published public var sign: String {
        didSet {
            UserDefaults.standard.set(sign, forKey: kSignKey)
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
    
    // 播放源快速缓存 [StreamID: PlayerSourcesContainer]
    @Published public var sourcesCache: [String: PlayerSourcesContainer] = [:]
    
    public init() {
        self.apiDomain = UserDefaults.standard.string(forKey: kApiDomainKey) ?? ""
        self.nodeDomain = UserDefaults.standard.string(forKey: kNodeDomainKey) ?? ""
        self.sign = UserDefaults.standard.string(forKey: kSignKey) ?? ""
    }
    
    public var hasCompleteConfig: Bool {
        let a = apiDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = nodeDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = sign.trimmingCharacters(in: .whitespacesAndNewlines)
        return !a.isEmpty && !n.isEmpty && !s.isEmpty
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
    
    private func cleanRawDomain(_ domain: String) -> String {
        var d = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.hasPrefix("http://") { d = String(d.dropFirst(7)) }
        if d.hasPrefix("https://") { d = String(d.dropFirst(8)) }
        if d.hasSuffix("/") { d = String(d.dropLast(1)) }
        return d
    }
    
    // MARK: - 1. 获取流列表 (过滤带 @ 字符的内部流)
    public func fetchStreamList(completion: (([NodeStreamInfo]) -> Void)? = nil) {
        guard hasCompleteConfig else {
            self.streamListError = "请完整填写配置参数"
            completion?([])
            return
        }
        
        let nodeBase = normalizeUrlPrefix(nodeDomain, defaultScheme: "http")
        let cAdmin = cleanRawDomain(apiDomain)
        let cNode = cleanRawDomain(nodeDomain)
        let encodedSign = sign.urlQueryComponentEncoded()
        
        // 候选请求地址列表（优先直连节点，若直连不通则尝试经由管理网关反向代理）
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
                    // 严格过滤掉带 @ 字符的内部流 ID
                    let list = rawList.filter { !$0.streamid.contains("@") }
                    self.streamList = list
                    if list.isEmpty {
                        self.streamListError = "当前节点暂无可展示的推流 (已过滤内部流)"
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
