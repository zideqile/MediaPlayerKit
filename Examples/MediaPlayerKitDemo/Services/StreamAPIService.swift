import Foundation
import Combine

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
    
    // MARK: - 1. 获取流列表
    public func fetchStreamList() {
        guard hasCompleteConfig else {
            self.streamListError = "请先配置域名、节点域名和 Sign 参数"
            return
        }
        
        let nodeBase = normalizeUrlPrefix(nodeDomain, defaultScheme: "http")
        let encodedSign = sign.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sign
        
        guard let url = URL(string: "\(nodeBase)/manager/streamclientipdata?sign=\(encodedSign)") else {
            self.streamListError = "节点 URL 格式不正确"
            return
        }
        
        self.isLoadingStreams = true
        self.streamListError = nil
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingStreams = false
                
                if let err = error {
                    self.streamListError = "获取流列表失败: \(err.localizedDescription)"
                    return
                }
                guard let data = data else {
                    self.streamListError = "返回数据为空"
                    return
                }
                
                do {
                    let resp = try JSONDecoder().decode(NodeStreamListResponse.self, from: data)
                    self.streamList = resp.streams ?? []
                    if self.streamList.isEmpty {
                        self.streamListError = "当前节点暂无活跃推流"
                    } else {
                        self.streamListError = nil
                    }
                } catch {
                    self.streamListError = "解析流列表失败: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    // MARK: - 2. 获取播放地址列表
    public func fetchPlayerSources(for streamId: String) {
        let trimmedId = streamId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return }
        
        let apiBase = normalizeUrlPrefix(apiDomain, defaultScheme: "https")
        guard let url = URL(string: "\(apiBase)/toolsapi/v1/player-sources/?streamId=\(trimmedId)") else {
            self.sourcesError = "播放地址 API 格式不正确"
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
                    return
                }
                guard let data = data else {
                    self.sourcesError = "播放地址返回为空"
                    return
                }
                
                do {
                    let resp = try JSONDecoder().decode(PlayerSourcesResponse.self, from: data)
                    self.playerSources = resp.playerSources
                    if (self.playerSources?.allSources.isEmpty ?? true) {
                        self.sourcesError = "未查询到可用播放地址"
                    }
                } catch {
                    self.sourcesError = "解析播放地址失败: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
}
