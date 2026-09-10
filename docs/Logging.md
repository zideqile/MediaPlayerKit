# 日志模块对标说明

实现位置：`Sources/MediaPlayerKit/VZLogger`。参考 Android `vzlogger/src/main/java/vzlogger`。
已接入 `export.Init` 与 `H5Player / MultiSourcePlayer` 的播放流程。调用 `export.Init` 会按配置启用日志输出；直接使用底层 MediaPlayerController 的调用方不经过这层业务埋点。

## 对标范围

| Android | Swift |
|---|---|
| Logger / InternalLogger | 默认及命名分组、动态添加/移除 Appender、flush/destroy |
| Debug / Info / Warn / Error / Fatal | LogLevel，原始值 0 / 1 / 2 / 3 / 4 |
| logD/I/W/E/F、logAD/AI/AW/AE/AF | 同名可变参数入口，普通日志与附加日志 |
| logSD/SI/SW/SE/SF | 数值统计；按 Android 行为不受文本级别过滤 |
| logMD/MI/MW/ME/MF、logMAD/MAI/MAW/MAE/MAF | `{}` 格式，相似参数合并；上传器延迟半个上传周期，控制台/文件立即输出 |
| ConsoleAppender / FileAppender | 控制台与追加文件；文件打开错误抛出，运行时错误可读取 lastError |
| ESUploadAppender / LogRecord | 普通、附加、统计日志、源信息、上下文、索引及 innerDrop |
| StaticRecordPart / DynamicRecordPart | 合并为记录构造；每 10 条记录附带 optionInfo |
| OldESUploader | `bury_content=stream_VPlayerLog-{env}_stat`，JSON 数组 POST |
| NewESUploader | Authorization 获取 type=2 地址，半有效期刷新，单对象 text/plain POST |
| StatisticsUploadTask | 单个在途请求、有界队列、失败后 1/2/3 秒异步重试 |

`LogConfig.level` 默认改为 Android 的 1（Info），修正旧注释及数值含义；已有显式数字需按新含义核对。
`categories` 保留用于配置兼容；Android 当前 InternalLogger 也未用它执行过滤。

## 独立使用日志模块的示例

```swift
let config = VPlayerConfig()
config.logConfig.level = LogLevel.info.rawValue
let options = InitConfig()
options.appenders = ["ConsoleAppender"] // 需要上传时显式加入 ESAppender
try Logger.initialize(config: config, initConfig: options, version: "your-sdk-version")
Logger.logI("initialized")
let playerLog = Logger.getLogger("player-1")
playerLog.onSourceChanged(srcUrl: "https://example.com/live.m3u8", srcType: "hls")
playerLog.logMI(95, "buffer {}", 30)
playerLog.logSI("fps", 30)
Logger.flushLog()
```

`VPlayerConfig.runtimeStateCollect.stateCountLimit` 控制附加日志数量（默认 10，负值按 0 处理）；`collectIntervalSeconds` 默认 3，MultiSourcePlayer 在播放时间回调中按此间隔采样；小于等于 0 禁用运行指标采样，不另建定时器。

`ESAppender` 使用 `appVZPlayerConfigJsonString` 的 forceUseNewESUploader（默认 true）、statLogIsAttachedToLog（默认 false）、statsMinUploadIntervalMs（默认 180000）。有鉴权回调且允许新协议时选新协议，否则选旧协议。`FileAppender` 使用 InitConfig.fileAppenderPath。

## 生命周期与边界

- Logger.initialize 只配置工厂，不取远程配置、不创建播放器。export.Init 还会记录初始化日志；启用 ESAppender 后，这些日志可由定时器上传。首次创建组才创建输出器和定时器。
- configure/initialize 会销毁上次配置及旧 Logger；调用方应重新获取分组。
- 工厂产生的 Appender 由 Logger 销毁且按对象去重；addAppender 添加的外部对象由调用方销毁，移除不会关闭共享对象。
- 自定义 Appender/transport 回调应快速返回，不要同步反调 Logger，避免跨串行队列等待。网络使用异步 URLSession。
- flush 表示封装并排队，**不代表服务器已收到**。业务播放器销毁通过 releaseLogger 释放自己的分组，上传器会尝试排空队列，最多等待 5 秒后关闭。全局 Logger.destroy 仍是立即关闭；超时或直接关闭不保证送达。
- 切源先封装旧源记录，再更新源信息。上传记录不受后续修改 VPlayerConfig 的影响。
- 上传默认最多 1000 条缓冲普通日志、默认 10 条附加日志、100 个统计名称；普通统计保留整个上传周期的样本，仅在等待普通日志一起上报时裁剪至最近 30 个值；消息截断至约 8 KiB。队列最多 10 条待上传记录，另加 1 个在途请求。容量溢出计入 innerDrop（附加日志/统计滚动窗口正常淘汰除外）。
- 分块目标约 10 KB；上下文及单条大消息可能超过目标，不承诺硬上限。文件为追加模式，尚无轮转/磁盘配额。
- 自定义 Appender 可实现 `makeLogMerger()`，为每个分组返回新合并器。Logger 负责 flush/destroy；Appender 不应缓存共享实例，以免一个分组关闭影响另一个分组。默认返回 nil，保持即时输出。该工厂接口提供 Android `getLogMerger()` 的扩展能力，并明确所有权。
- `LogUploadPolicy.maxStatisticSamplesPerName` 默认为 nil，与 Android 普通统计保留规则一致；需要内存限制时可以显式设置，超出样本数计入 innerDrop。Android 等待分支的正常滚动裁剪不计入丢失。
- 相似度沿用 Android 字符串编辑距离与数字相对差；字符串超过 2048 字符只做精确匹配，避免耗时过大。
- 尚未移植 Android 的远程调试配置获取、部分业务埋点常量和请求级底层采样；调用位置已使用 Swift 编译期字面量实现。当前已经接入的字段及尚未接入的数据见下文。

## 验证

`Tests/MediaPlayerKitTests/LoggingTests.swift` 使用假 transport/uploader，不访问真实服务器。
Linux 可通过独立临时 Swift Package 编译 VZLogger 文件，并仅在临时配置副本移除 `@objc` 属性运行测试；正式源码不做该转换。
完整 Apple 平台编译与真实日志服务联调仍需 Xcode/设备环境。

## SDK 播放流程输出

每个 MultiSourcePlayer 实例使用独立分组，避免多个播放器的 srcUrl 相互覆盖。export.Init 按 InitConfig 写入用户、topic、设备信息并生成会话 userIdUuid；日志初始化失败可通过 export.lastLoggingError 检查，播放仍可继续。

- 文本：播放、暂停、恢复、seek、源列表、尝试创建、状态变化、首帧、单次错误、内核回退、换源、最终错误、结束和销毁。
- 与 Android 同含义的统计：source_hls / source_hls_hevc 等源类型计数、first_frame_time（毫秒）、失败尝试的 player_time（毫秒）、有明确视频尺寸时的 has_video=1。
- iOS 专属字段：ios_player_avplayer_error_code / ios_player_ksmeplayer_error_code，避免复用 Android Exo/IJK/Agora 的编号；ios_stall_episode_ms 是单次缓冲事件时长，不是 Android 滑动窗口 stall_duration。
- 运行指标：KSPlayer 的实际显示 FPS 使用 fps，轨道标称帧率使用 frame_rate。引擎读取字节、AVPlayer 网络传输字节、丢帧、丢包、请求数使用 ios_ 前缀区分口径；详见下表。
- 尚未采集：TS/M3U8 每请求的耗时、字节、状态码和 TCP 层速度；累计读取/传输字节的采样速率不等同于 TCP 速度。
- 未调用 export.Init 时，播放器仍可运行；也可由宿主先调用 Logger.configure / initialize 设置自定义日志输出。


## 类名、函数名和行号

Android 的 LogLocationMethodVisitor 通过 ASM 注入位置；Swift 使用调用处的 `#fileID`、`#function`、`#line`，无需运行时解析调用栈。普通、附加、合并日志统一带 `[类型.函数:行号]` 前缀，控制台、文件和 ES 上传共用同一消息。统计名称保持原样。

SDK 的 PlaybackDiagnostics 显式标注 MultiSourcePlayer 并逐层传递函数、行号，因此位置指向业务调用处。不同调用位置的消息不会互相合并。

Swift 没有自动获取封闭类型名的字面量；默认从文件名推导类型名。一个文件包含多个类型、扩展文件名与类型名不一致时，调用者应显式提供 `typeName`：

```swift
Logger.logI("play", typeName: String(describing: Self.self))
// 示例：[MultiSourcePlayer.play():123] play
```

自定义日志包装函数也应声明上述位置参数的默认值，并显式向 Logger 转发；否则位置会指向包装函数。原有直接调用方式无需改动。

## 运行指标口径

| 字段 | 来源及单位 |
| --- | --- |
| fps | KSPlayer DynamicInfo.displayFPS，实际显示帧/秒；AVPlayer 不提供时省略 |
| frame_rate | 当前视频轨道标称帧率，帧/秒 |
| ios_bytes_read_delta / ios_bytes_read_per_second | KSPlayer 读取字节的采样增量 / 字节每秒，可包含本地读取 |
| ios_network_bytes_delta / ios_network_bytes_per_second | AVPlayer access log 累计传输字节的采样增量 / 字节每秒 |
| ios_dropped_video_frames_delta | 采样期间丢弃的视频帧数 |
| ios_dropped_video_packets_delta | KSPlayer 采样期间丢弃的视频包数 |
| ios_media_requests_delta | AVPlayer 采样期间媒体请求数 |
| ios_observed_bitrate_bps | AVPlayer 最近 access log 事件的 observedBitrate，bit/s |

引擎只返回可获取的指标，未知值为 nil；无效数值不上传。首个样本只建立计数基线，之后使用单调时钟计算增量和速度。切源、切引擎、暂停后重置基线，计数回退或指标缺失时重新建立基线，不输出负增量。播放或缓冲状态下采样，暂停不采样；时间回调停止时不会额外轮询。统计字段写入 logSI，并将该次指标写入受 stateCountLimit 限制的附加日志。

AVPlayer 字段来自 [Apple AVPlayerItemAccessLogEvent 文档](https://developer.apple.com/documentation/avfoundation/avplayeritemaccesslogevent)。这些聚合观测值并非逐请求网络埋点，也不能替代 Android 所有底层指标。

## H5 / JS 对标补充

H5 属性设置通过 MultiSourcePlayer 记录音量、静音、循环、倍速操作；沿用播放器分组和源上下文，不另建全局日志组。H5 setter 的 JSON 格式、类型或范围错误记录 Error，并返回 false，位置指向 H5Player 的实际校验处。不会把参数错误当成播放失败或触发 PlayerWARN。

时间要求非负且可安全转换为 Int64；音量范围 0...1；倍速为正且可表示为 Float；布尔属性要求 JSON boolean。参数错误不改变原值。JS 页面日志仍用于 Demo 显示，不自动上传任意页面日志。

### WKWebView 请求回执

原有 `{method, paramsJson}` 消息继续有效。标准 SDK 方法可增加字符串 `requestId`，PlayerBridge 通过 `window.vzPlayerBridge.onResponse(response)` 回传：

```javascript
// 请求
{ method: 'getVolume', paramsJson: '{}', requestId: 'query-1' }
// 成功
{ requestId: 'query-1', ok: true, result: { volume: 0.5 } }
// 失败
{ requestId: 'query-1', ok: false, error: 'invalid_parameters_or_rejected' }
```

未知方法返回 unsupported_method，播放器不存在返回 player_unavailable；无返回值的操作 result 为 null。回执确认方法已处理/受理，实际开始播放仍以 playing 等事件为准。SendEvent 仅支持 NEXT_SOURCE 和 SWITCH_SOURCE，NEXT_SOURCE 的受理回执不代表已成功切源。

Demo 的 player.js 提供 `await window.vzPlayerBridge.request('getVolume')` 和 `request('setVolume', {volume: 0.5})`，支持 iOS 异步回执、Android 同步接口结果归一化、10 秒超时及页面退出清理。播放与属性控制已接入该接口。Demo 专属节点调度命令继续走 sendCmd，不在标准请求协议范围内。宿主接入 SDK PlayerBridge 时，需要自行提供 onResponse 或复用 Demo 中的 Promise 适配代码。

验证：H5BridgeTests 覆盖属性校验、播放器日志分组、getter/setter 回执及失败；`node Tests/JavaScript/BridgeTests.cjs` 覆盖回执关联、失败、超时、页面清理和 Android 接口适配。
