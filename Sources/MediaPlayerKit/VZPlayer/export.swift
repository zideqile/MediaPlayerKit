import Foundation

/// 播放器全局导出与入口类 (1:1 严格对标 Android vzplayer 的 xyz.doikki.vzplayer.export)
@objc(export)
public final class export: NSObject {
    private static var playerConfig = VPlayerConfig()
    private static var initConfig: InitConfig?
    
    /// 获取当前 SDK 版本号 (1:1 对标 Android export.GetVersion())
    @objc public static func GetVersion() -> String {
        return "2"
    }
    
    /// 初始化播放器系统与全局配置 (1:1 对标 Android export.Init())
    @objc public static func Init(_ initConfig: InitConfig?, _ configJson: String?) {
        if let config = VPlayerConfig.fromJson(configJson) as VPlayerConfig? {
            self.playerConfig = config
        }
        self.initConfig = initConfig
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

/// 兼容别名
@objc(VZPlayerExport)
public final class VZPlayerExport: NSObject {
    @objc public static func GetVersion() -> String { export.GetVersion() }
    @objc public static func Init(initConfig: InitConfig?, configJson: String?) { export.Init(initConfig, configJson) }
    @objc public static func CreateVZPlayer(_ playerView: MediaPlayerView) -> IH5Player { export.CreateVZPlayer(playerView) }
    @objc public static func CreateVZPlayer(playerView: MediaPlayerView) -> IH5Player { export.CreateVZPlayer(playerView) }
}

public typealias Export = export

