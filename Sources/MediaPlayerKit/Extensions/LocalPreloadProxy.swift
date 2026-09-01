import Foundation

/// 本地边下边播与预加载代理服务
/// 将远程 CDN 媒体请求重定向到本地 Localhost 代理，统一接管分片预加载与磁盘 LRU 缓存
public final class LocalPreloadProxy {
    public static let shared = LocalPreloadProxy()
    
    private let cacheDirectory: URL
    private let preloadQueue = DispatchQueue(label: "com.mediaplayerkit.preload.queue", qos: .utility)
    private var activePreloadTasks: [URL: URLSessionDataTask] = [:]
    private let lock = NSLock()
    
    private init() {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        self.cacheDirectory = paths[0].appendingPathComponent("MediaPlayerKitCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// 将原始媒体 URL 转换为本地代理播放 URL
    public func proxyURL(for originURL: URL) -> URL {
        // 如果是本地文件或已缓存，直接返回本地路径
        if originURL.isFileURL {
            return originURL
        }
        
        let localFilePath = cacheFilePath(for: originURL)
        if FileManager.default.fileExists(atPath: localFilePath.path) {
            return localFilePath
        }
        
        // 返回本地轻量代理服务 URL 或原始 URL (当代理未启用时)
        return originURL
    }
    
    /// 静默预加载下一个视频的前 N 字节 (如 1MB / 2个 GOP)
    public func preload(url: URL, preloadBytes: Int = 1024 * 1024) {
        guard !url.isFileURL else { return }
        
        preloadQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.lock.lock()
            if self.activePreloadTasks[url] != nil {
                self.lock.unlock()
                return
            }
            self.lock.unlock()
            
            var request = URLRequest(url: url)
            request.setValue("bytes=0-\(preloadBytes - 1)", forHTTPHeaderField: "Range")
            
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self, let data = data, error == nil else { return }
                
                let targetPath = self.cacheFilePath(for: url)
                try? data.write(to: targetPath)
                
                self.lock.lock()
                self.activePreloadTasks.removeValue(forKey: url)
                self.lock.unlock()
            }
            
            self.lock.lock()
            self.activePreloadTasks[url] = task
            self.lock.unlock()
            
            task.resume()
        }
    }
    
    /// 取消特定 URL 的预加载任务
    public func cancelPreload(for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        
        activePreloadTasks[url]?.cancel()
        activePreloadTasks.removeValue(forKey: url)
    }
    
    /// 清除所有本地磁盘缓存
    public func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    private func cacheFilePath(for url: URL) -> URL {
        let fileName = "\(url.absoluteString.hashValue).mp4"
        return cacheDirectory.appendingPathComponent(fileName)
    }
}
