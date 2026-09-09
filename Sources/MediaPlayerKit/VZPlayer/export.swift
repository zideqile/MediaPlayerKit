import Foundation

/// 播放器全局导出与入口类 (1:1 严格对标 Android vzplayer 的 xyz.doikki.vzplayer.export)
@objc(export)
public final class export: NSObject {
    private static var playerConfig = VPlayerConfig()
    private static var initConfig: InitConfig?
    @objc public private(set) static var lastLoggingError: NSError?
    
    /// 获取当前 SDK 版本号 (1:1 对标 Android export.GetVersion())
    @objc public static func GetVersion() -> String {
        return "2"
    }
    
    /// 初始化播放器系统与全局配置 (1:1 对标 Android export.Init())
    @objc public static func Init(_ initConfig: InitConfig?, _ configJson: String?) {
        let config = VPlayerConfig.fromJson(configJson)
        let options = initConfig ?? InitConfig()
        if initConfig != nil {
            config.userId = options.userId
            config.topicId = options.topicId
        }
        config.userIdUuid = "\(config.userId)_\(UUID().uuidString)"
        self.playerConfig = config
        self.initConfig = options
        lastLoggingError = nil
        do {
            try Logger.initialize(config: config, initConfig: options, version: GetVersion())
            Logger.logI("Logger.init", "env:", config.env, "version:", GetVersion(), "userId:", config.userId)
        } catch {
            // A log sink failure must not prevent media playback or reuse stale credentials.
            lastLoggingError = error as NSError
            Logger.configure(level: .warn) { _ in [ConsoleAppender()] }
            Logger.logE("Logger initialization failed:", error.localizedDescription)
        }
    }
    
    @objc public static func Init(initConfig: InitConfig?, configJson: String?) {
        Init(initConfig, configJson)
    }
    
    /// 创建播放器实例，返回 IH5Player 统一门面操作对象 (1:1 对标 Android export.CreateVZPlayer())
    @objc public static func CreateVZPlayer(_ playerView: MediaPlayerView) -> IH5Player {
        let player = H5Player(playerView: playerView, config: playerConfig)
        return player
    }
    
    @objc public static func CreateVZPlayer(playerView: MediaPlayerView) -> IH5Player {
        return CreateVZPlayer(playerView)
    }
}

