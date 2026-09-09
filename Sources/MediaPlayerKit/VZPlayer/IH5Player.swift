import Foundation

/// H5 事件与错误回调监听器 (1:1 严格对标 Android vzplayer 的 IH5Player.H5EventListener)
@objc public protocol VZH5EventListener: AnyObject {
    /// 标准状态事件通知 ("play", "playing", "pause", "ended", "waiting", "canplaythrough", "PlayerWARN")
    func onEvent(_ eventName: String)
    
    /// 播放严重错误通知
    func onError(_ code: Int, errMsg: String)
    
    /// 播放进度定时心跳 (单位: 秒)
    func onTimeUpdate(_ currentTime: Int64)
}

/// 对外业务与 H5 / JSBridge 统一门面协议 (1:1 严格对标 Android vzplayer 的 IH5Player.java)
@objc public protocol IH5Player: AnyObject {
    /// 注册外部 H5 事件监听器 (对标 Android SetOnH5EventListener)
    @objc func SetOnH5EventListener(_ listener: VZH5EventListener?)
    
    // MARK: - 基础播放控制 (对标 Android IH5Player.java)
    @objc func play()
    @objc func pause()
    @objc func resume()
    @objc func destroy()
    
    /// 设置多播放源列表 (支持优先级与自动容错轮询)
    @objc func setSources(_ sources: [VZPlayerSource])
    
    /// 设置运行时策略配置
    @objc func setConfig(_ config: VZPlayerConfig)
    
    /// 向播放器派发自定义事件 (如 NEXT_SOURCE, SWITCH_SOURCE)
    @objc func SendEvent(_ eventName: String, _ paramsJson: String)
    
    /// 手动指定切换到某个播放源索引
    @objc func switchSource(index: Int) -> Bool
    
    // MARK: - H5 风格属性 Getters / Setters (JSON 格式入参出参，对标 Android @JavascriptInterface)
    
    /// 获取当前播放进度: {"currentTime": 120}
    @objc func get_currentTime() -> String
    /// 跳转进度: {"currentTime": 60}
    @objc func set_currentTime(_ currentTime: String) -> Bool
    
    /// 获取视频总时长: {"duration": 3600}
    @objc func get_duration() -> String
    
    /// 获取是否暂停: {"pause": true/false}
    @objc func get_pause() -> String
    
    /// 获取音量 (0.0 ~ 1.0): {"volume": 0.8}
    @objc func get_volume() -> String
    /// 设置音量: {"volume": 0.5}
    @objc func set_volume(_ volume: String) -> Bool
    
    /// 获取是否静音: {"muted": true/false}
    @objc func get_muted() -> String
    /// 设置静音: {"muted": true}
    @objc func set_muted(_ parametersJson: String) -> Bool
    
    /// 获取视频自然宽度: {"videoWidth": 1920}
    @objc func get_videoWidth() -> String
    /// 获取视频自然高度: {"videoHeight": 1080}
    @objc func get_videoHeight() -> String
    
    /// 获取是否循环播放: {"loop": true/false}
    @objc func get_loop() -> String
    /// 设置是否循环播放: {"loop": true}
    @objc func set_loop(_ parametersJson: String) -> Bool
    
    /// 获取播放倍速: {"speed": 1.0}
    @objc func get_speed() -> String
    /// 设置播放倍速: {"speed": 1.5}
    @objc func set_speed(_ parametersJson: String) -> Bool
    
    /// 获取已缓冲进度: {"length": 1, "start": 0, "end": 25}
    @objc func get_buffered() -> String
    
    /// 获取当前生效的播放源详情 JSON
    @objc func get_currentsource() -> String
}
