import Foundation

/// 日志与上报服务器配置
@objc public final class VZLogServerConfig: NSObject, Codable {
    @objc public var domain: String = "lgtx-test.vzan.com"
    @objc public var port: Int = 443
    @objc public var path: String = "/live/zbmonitor"
    @objc public var secure: Bool = true
}

/// 日志级别与周期配置
@objc public final class VZLogConfig: NSObject, Codable {
    @objc public var uploadIntervalSeconds: Int = 30
    @objc public var level: Int = 2 // 1: Verbose, 2: Info, 3: Warn, 4: Error
}

/// 播放器运行时策略配置 (对标 Android vzplayer 的 VPlayerConfig)
@objc public final class VZPlayerConfig: NSObject, Codable {
    @objc public var loop: Bool = false
    @objc public var autoplay: Bool = true
    @objc public var muted: Bool = false
    @objc public var volume: Float = 1.0
    @objc public var speed: Float = 1.0
    
    @objc public var topicId: String = ""
    @objc public var streamId: String = ""
    @objc public var userId: Int64 = -1
    @objc public var userIdUuid: String = ""
    
    @objc public var isLive: Bool = false
    @objc public var env: String = "dev" // "dev", "test", "prod"
    
    @objc public var logConfig: VZLogConfig = VZLogConfig()
    @objc public var logServerConfig: VZLogServerConfig = VZLogServerConfig()
    
    @objc public var appVZPlayerConfigJsonString: String = ""
    
    public static func fromJson(_ jsonString: String?) -> VZPlayerConfig {
        guard let jsonString = jsonString, !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8),
              let config = try? JSONDecoder().decode(VZPlayerConfig.self, from: data) else {
            return VZPlayerConfig()
        }
        return config
    }
}

/// 全局初始化配置 (对标 Android vzplayer 的 InitConfig)
@objc public final class VZInitConfig: NSObject {
    @objc public var fileAppenderPath: String?
    @objc public var appenders: [String] = ["ConsoleAppender", "ESAppender"]
    @objc public var isDebug: Bool = false
    @objc public var isDebugMode: Bool = false
    @objc public var userId: Int64 = -1
    @objc public var topicId: String = ""
    @objc public var deviceInfo: String = ""
    @objc public var customInfo: String = ""
    @objc public var clusterDomain: String = "vzan.com"
    @objc public var getAuthorizationCallback: (() -> String)?
    
    @objc public override init() {
        super.init()
    }
}
