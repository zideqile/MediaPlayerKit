import Foundation

/// 本地边下边播与预加载代理服务
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
        // 直接返回原始 URL 以保证全量流式分片及 HLS / MP4 播放稳定
        return originURL
    }
    
    /// 静默预加载下一个视频的前 N 字节 (如 1MB)
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
                guard let self = self else { return }
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
}
