import Foundation

/// 播放器全局导出与入口类 (对标 Android vzplayer 的 xyz.doikki.vzplayer.export)
@objc(VZPlayerExport)
public final class VZPlayerExport: NSObject {
    private static var playerConfig = VZPlayerConfig()
    private static var initConfig: VZInitConfig?
    
    /// 获取当前 SDK 版本号 (对标 export.GetVersion())
    @objc public static func GetVersion() -> String {
        return "2"
    }
    
    /// 初始化播放器系统与全局日志/上报配置 (对标 export.Init())
    @objc public static func Init(initConfig: VZInitConfig?, configJson: String?) {
        if let config = VZPlayerConfig.fromJson(configJson) as VZPlayerConfig? {
            self.playerConfig = config
        }
        self.initConfig = initConfig
    }
    
    /// 创建 VZPlayer 实例，返回 IPlayer 统一操作对象 (对标 export.CreateVZPlayer())
    @objc public static func CreateVZPlayer(_ playerView: MediaPlayerView) -> IPlayer {
        let player = VZH5Player(playerView: playerView, config: playerConfig)
        return player
    }
    
    @objc public static func CreateVZPlayer(playerView: MediaPlayerView) -> IPlayer {
        return CreateVZPlayer(playerView)
    }
}

/// 兼容 Android 原生双端无缝类名 export
@objc(export)
public final class export: NSObject {
    @objc public static func GetVersion() -> String {
        return VZPlayerExport.GetVersion()
    }
    
    @objc public static func Init(_ initConfig: VZInitConfig?, _ configJson: String?) {
        VZPlayerExport.Init(initConfig: initConfig, configJson: configJson)
    }
    
    @objc public static func Init(initConfig: VZInitConfig?, configJson: String?) {
        VZPlayerExport.Init(initConfig: initConfig, configJson: configJson)
    }
    
    @objc public static func CreateVZPlayer(_ playerView: MediaPlayerView) -> IPlayer {
        return VZPlayerExport.CreateVZPlayer(playerView)
    }
    
    @objc public static func CreateVZPlayer(playerView: MediaPlayerView) -> IPlayer {
        return VZPlayerExport.CreateVZPlayer(playerView)
    }
}
