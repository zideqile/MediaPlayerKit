import Foundation

/// 针对短视频 Feed 滑动列表的播放器实例池管理器
/// 通过预热和复用播放器实例，实现毫秒级起播并彻底消除滑动时的内存抖动
public final class PlayerPoolManager {
    public static let shared = PlayerPoolManager()
    
    private let lock = NSLock()
    private var availablePool: [MediaPlayerController] = []
    private var activeSet: Set<MediaPlayerController> = []
    
    /// 实例池最大容量（默认维持 3 个预热实例：当前播放、上一个、下一个）
    public var maxPoolSize: Int = 3
    
    private init() {
        warmUp()
    }
    
    /// 预热实例池
    public func warmUp() {
        lock.lock()
        defer { lock.unlock() }
        
        while availablePool.count < maxPoolSize {
            let player = MediaPlayerController()
            availablePool.append(player)
        }
    }
    
    /// 从池中取出一个可用的播放器实例
    public func dequeuePlayer() -> MediaPlayerController {
        lock.lock()
        defer { lock.unlock() }
        
        let player: MediaPlayerController
        if let reusedPlayer = availablePool.popLast() {
            player = reusedPlayer
        } else {
            player = MediaPlayerController()
        }
        activeSet.insert(player)
        return player
    }
    
    /// 归还并重置播放器实例
    public func recyclePlayer(_ player: MediaPlayerController) {
        lock.lock()
        defer { lock.unlock() }
        
        player.reset() // 重置底层解码器与纹理状态，保持实例不销毁
        activeSet.remove(player)
        
        if availablePool.count < maxPoolSize {
            availablePool.append(player)
        }
    }
    
    /// 清空并释放所有空闲实例（如收到系统内存警告时调用）
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        for player in availablePool {
            player.stop()
        }
        availablePool.removeAll()
    }
}
