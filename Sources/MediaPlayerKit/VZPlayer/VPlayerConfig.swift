import Foundation

/// 日志与上报服务器配置 (1:1 对标 Android vzplayer 的 LogServerConfig.java)
@objc(LogServerConfig)
public final class LogServerConfig: NSObject, Codable {
    @objc public var domain: String = "lgtx-test.vzan.com"
    @objc public var port: Int = 443
    @objc public var path: String = "/live/zbmonitor"
    @objc public var secure: Bool = true
    public override init() { super.init() }

    public required init(from decoder: Decoder) throws {
        super.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        domain = try values.decodeIfPresent(String.self, forKey: .domain) ?? domain
        port = try values.decodeIfPresent(Int.self, forKey: .port) ?? port
        path = try values.decodeIfPresent(String.self, forKey: .path) ?? path
        secure = try values.decodeIfPresent(Bool.self, forKey: .secure) ?? secure
    }

}

/// 日志级别与周期配置 (1:1 对标 Android vzplayer 的 LogConfig.java)
@objc(LogConfig)
public final class LogConfig: NSObject, Codable {
    @objc public var uploadIntervalSeconds: Int = 30
    @objc public var level: Int = 2 // 1: Verbose, 2: Info, 3: Warn, 4: Error
    public override init() { super.init() }

    public required init(from decoder: Decoder) throws {
        super.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        uploadIntervalSeconds = try values.decodeIfPresent(Int.self, forKey: .uploadIntervalSeconds) ?? uploadIntervalSeconds
        level = try values.decodeIfPresent(Int.self, forKey: .level) ?? level
    }

}

/// 播放器运行时策略配置 (1:1 严格对标 Android vzplayer 的 VPlayerConfig.java)
@objc(VPlayerConfig)
public final class VPlayerConfig: NSObject, Codable {
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
    @objc public var isHardwareDecode: Bool = true
    @objc public var headers: [String: String] = [:]
    
    @objc public var logConfig: LogConfig = LogConfig()
    @objc public var logServerConfig: LogServerConfig = LogServerConfig()
    
    @objc public var appVZPlayerConfigJsonString: String = ""
    
    enum CodingKeys: String, CodingKey {
        case loop, autoplay, muted, volume, speed
        case topicId, streamId, userId, userIdUuid
        case isLive, env, isHardwareDecode, headers
        case logConfig, logServerConfig
        case appVZPlayerConfigJsonString
    }

    public override init() { super.init() }

    public required init(from decoder: Decoder) throws {
        super.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        loop = try values.decodeIfPresent(Bool.self, forKey: .loop) ?? loop
        autoplay = try values.decodeIfPresent(Bool.self, forKey: .autoplay) ?? autoplay
        muted = try values.decodeIfPresent(Bool.self, forKey: .muted) ?? muted
        volume = try values.decodeIfPresent(Float.self, forKey: .volume) ?? volume
        speed = try values.decodeIfPresent(Float.self, forKey: .speed) ?? speed
        topicId = try values.decodeIfPresent(String.self, forKey: .topicId) ?? topicId
        streamId = try values.decodeIfPresent(String.self, forKey: .streamId) ?? streamId
        userId = try values.decodeIfPresent(Int64.self, forKey: .userId) ?? userId
        userIdUuid = try values.decodeIfPresent(String.self, forKey: .userIdUuid) ?? userIdUuid
        isLive = try values.decodeIfPresent(Bool.self, forKey: .isLive) ?? isLive
        env = try values.decodeIfPresent(String.self, forKey: .env) ?? env
        isHardwareDecode = try values.decodeIfPresent(Bool.self, forKey: .isHardwareDecode) ?? isHardwareDecode
        headers = try values.decodeIfPresent([String: String].self, forKey: .headers) ?? headers
        logConfig = try values.decodeIfPresent(LogConfig.self, forKey: .logConfig) ?? logConfig
        logServerConfig = try values.decodeIfPresent(LogServerConfig.self, forKey: .logServerConfig) ?? logServerConfig
        appVZPlayerConfigJsonString = try values.decodeIfPresent(String.self, forKey: .appVZPlayerConfigJsonString) ?? appVZPlayerConfigJsonString
    }

    public static func fromJson(_ jsonString: String?) -> VPlayerConfig {
        guard let jsonString = jsonString, !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8),
              let config = try? JSONDecoder().decode(VPlayerConfig.self, from: data) else {
            return VPlayerConfig()
        }
        return config
    }
}

/// 全局初始化配置 (1:1 严格对标 Android vzplayer 的 InitConfig.java)
@objc(InitConfig)
public final class InitConfig: NSObject {
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

