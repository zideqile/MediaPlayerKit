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
- 与 Android 同含义的统计（字段名称 100% 严格同名对标 Android vzplayer）：
  - `source_<type>` / `current_source_<type>`：添加源与当前起播源类型打点
  - `first_frame_time`：首帧渲染耗时（毫秒）
  - `has_video`：是否有有效视频画面尺寸（1/0）
  - `frame_rate`：标称视频帧率
  - `player_time`：起播到就绪/报错的时长（毫秒）
  - `player_type`：内核类型枚举值
  - `player_<engine>_error_code`：内核错误码（对标 Android `player_<type>_error_code`）
  - `internal_error`：内部非致命重试与故障计数
  - `stall_duration`：单次卡顿时长（毫秒）
  - `stall_count`：卡顿次数计数
  - `total_stall`：累计卡顿总时长（毫秒）
  - `on_waiting`：进入缓冲态计数
  - `on_playing`：进入播放态计数
  - `current_time`：退出实例时播放进度时间戳（毫秒）
  - `close_normal` / `player_<engine>_close_normal`：正常退出为 1，异常为 0
  - `drop`：采样周期丢帧数（对标 Android `drop`）
  - `drop_count`：累计丢帧总数（对标 Android `drop_count`）
- 聚合网络与质量指标：除对标 Android vzplayer 的既有字段（`fps`、`frame_rate`、`drop`、`drop_count` 等）严格同名外，其余运行时网络、读取、丢包与请求指标均遵循“言简意赅”原则，消除冗余的平台特异前缀（如 `ios_`）与过度修饰（如 `_delta`、`_per_second`、`_bps`）：
  - `net_bytes`：采样周期网络传输增量字节数
  - `net_speed`：采样周期网络下载速率（字节/秒）
  - `read_bytes`：采样周期引擎读取增量字节数
  - `read_speed`：采样周期引擎读取速率（字节/秒）
  - `drop_packet`：采样周期丢弃的视频数据包数
  - `media_requests`：采样周期完成的媒体请求增量数
- 尚未采集：TS/M3U8 细粒度逐切片请求的耗时、字节、HTTP 状态码（AVPlayer 守护进程接管下载，不提供切片级网络拦截）。
- 未调用 export.Init 时，播放器仍可运行；也可由宿主先调用 Logger.configure / initialize 设置自定义日志输出。


## 类名、函数名和行号

Android 的 LogLocationMethodVisitor 通过 ASM 注入位置；Swift 使用调用处的 `#fileID`、`#function`、`#line`，无需运行时解析调用栈。显示时去掉方法参数签名（例如 `player(_:stateDidChange:)` 显示为 `player`）。普通、附加、合并日志统一带 `[类型.函数:行号]` 前缀，控制台、文件和 ES 上传共用同一消息。统计名称保持原样。

SDK 的 PlaybackDiagnostics 显式标注 MultiSourcePlayer 并逐层传递函数、行号，因此位置指向业务调用处。不同调用位置的消息不会互相合并。

Swift 没有自动获取封闭类型名的字面量；默认从文件名推导类型名。一个文件包含多个类型、扩展文件名与类型名不一致时，调用者应显式提供 `typeName`：

```swift
Logger.logI("play", typeName: String(describing: Self.self))
// 示例：[MultiSourcePlayer.play:123] play
```

自定义日志包装函数也应声明上述位置参数的默认值，并显式向 Logger 转发；否则位置会指向包装函数。原有直接调用方式无需改动。

## 运行指标口径

| 字段 | 来源及单位 | 对标 / 简化规范 |
| --- | --- | --- |
| fps | KSPlayer DynamicInfo.displayFPS，实际显示帧/秒；AVPlayer 不提供时省略 | 对标 Android vzplayer `fps` |
| frame_rate | 当前视频轨道标称帧率，帧/秒 | 对标 Android vzplayer `frame_rate` |
| drop | 采样周期内丢弃的视频帧数 | 对标 Android vzplayer `drop` |
| drop_count | 累计丢弃的视频帧数 | 对标 Android vzplayer `drop_count` |
| bandwidth | AVPlayer access log 观测吞吐率，bit/s | 沿用 vplayer bandwidth 的吞吐率含义；观测来源与估算方法不同 |
| net_bytes / net_speed | 采样周期内网络下行增量字节 / 网络下载速率（字节/秒） | 简化命名，言简意赅 |
| read_bytes / read_speed | KSPlayer 采样周期内读取增量字节 / 读取速率（字节/秒） | 简化命名，言简意赅 |
| drop_packet | KSPlayer 采样周期内丢弃的视频数据包数 | 对称 `drop`，言简意赅 |
| media_requests | AVPlayer 采样周期内媒体请求增量数 | 简化命名，言简意赅 |

引擎只返回可获取的指标，未知值为 nil；无效数值不上传。首个样本只建立计数基线，之后使用单调时钟计算增量和速度。切源、切引擎、暂停后重置基线，计数回退或指标缺失时重新建立基线，不输出负增量。播放或缓冲状态下采样，暂停不采样；定时采样不依赖进度回调。统计字段写入 logSI，并将该次指标写入受 stateCountLimit 限制的附加日志。

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

SDK 的 vzplayer-bridge.js 提供 `await window.vzPlayerBridge.request('getVolume')` 和 `request('setVolume', {volume: 0.5})`，支持 iOS 异步回执、Android 同步接口结果归一化、10 秒超时及页面退出清理。播放与属性控制已接入该接口。Demo 专属节点调度命令继续走 sendCmd，不在标准请求协议范围内。宿主通过 PlayerBridge.installJavaScript(in:) 安装 SDK 自带的 Promise 适配代码，并注册 PlayerBridge 消息处理器。

验证：H5BridgeTests 覆盖属性校验、播放器日志分组、getter/setter 回执及失败；`node Tests/JavaScript/BridgeTests.cjs` 覆盖回执关联、失败、超时、页面清理和 Android 接口适配。


### 独立 JS 桥接资源与 Android 事件边界

可复用脚本为 `Sources/MediaPlayerKit/Resources/vzplayer-bridge.js`，不依赖 Demo DOM。SPM 和 CocoaPods 均包含该资源。iOS 在创建 WKWebView 前调用：

```swift
let content = WKUserContentController()
try PlayerBridge.installJavaScript(in: content)
// 还需由宿主注册消息处理器，并持有 PlayerBridge、设置 webView。
content.add(bridge, name: "vzPlayerBridge")
```

脚本在主 frame 的 document start 注入；重复安装同一脚本不重复注册。宿主销毁 WebView 时移除消息处理器。Demo 已使用该资源，不再维护独立的桥接实现。普通网页或 Android 页面可将同一 JS 文件作为脚本加载。

Android 源码 IPlayer.PlayerEvent 实际只有 NEXT_SOURCE 和 SWITCH_PLAYER。IH5Player.SendEvent 接收 Java 枚举及 JSON 字符串；该 Java 接口不是已验证的 JS 注入协议。iOS 的 SWITCH_SOURCE / switchSource 为指定源索引扩展，不能声称 Android 原生支持相同事件。

Android 宿主需提供可供 JS 调用的包装方法，将事件字符串转换为原生枚举，再显式配置适配函数：

```javascript
window.vzPlayerBridge.configure({
  // 此方法由 Android 宿主实现并暴露，不是 vzplayer 已有接口的声明。
  androidSendEvent: (eventName, paramsJson) =>
    window.AndroidBridge.sendPlayerEvent(eventName, paramsJson)
});
await window.vzPlayerBridge.request('SendEvent', {
  eventName: 'NEXT_SOURCE', params: {}
});
```

未配置事件适配器返回 android_event_adapter_required；未知 Android 事件返回 unsupported_event。Android 的 SWITCH_PLAYER 通过此显式适配器转交宿主；iOS 尚不支持该事件，不将它误映射成切源。适配函数可返回同步结果或 Promise，false 表示拒绝，void 仅表示已受理。Android 包装和双端真机行为仍需宿主联调验证。


## attachedLogs：近期播放状态上下文

每个 MultiSourcePlayer 的诊断分组独立采集状态。创建播放内核后立即采样，之后按
`runtimeStateCollect.collectIntervalSeconds`（默认 3 秒）在主运行循环定时采样；
状态变化、播放操作和错误也触发采样。定时器不依赖播放进度回调，因此卡顿时仍可采样。
间隔小于等于 0 时关闭定时采样，保留事件采样。销毁时停止采集，闭包弱引用播放器。

状态通过 `logAI` 写入附加日志，包含 `videoCurrentTime`、`duration`、`playbackRate`、
`bufferedEnd`、`playState`、`paused`、`muted`、视频尺寸、`lastEvent` 和本次内核尝试的
`totalPlayTime`（秒，仅累计 playing 状态）。不可用的非有限数值输出 null。
原生 SDK 没有 HTML readyState；bufferedEnd 是媒体时间轴上的缓冲终点，不伪造浏览器缓冲区间。

ESAppender 按 `runtimeStateCollect.stateCountLimit` 保留最近 N 条附加日志（默认沿用
SDK 的 10 条，可配置为 100；0 表示不保留）。上传后保留该滚动窗口，后续记录可重复携带
上下文。只有附加日志时，定时上传、flush 和 finish 都不会单独上传；普通日志或已有统计
上传时会附带上下文。statLogs 的独立上传策略保持不变。

切源或切换内核前先提交旧日志，再清空旧状态，避免新源记录携带旧源状态。
启用 ConsoleAppender 时，附加日志在 ES 上传打包时集中打印，不在采集时立即打印；
仅启用 ConsoleAppender 而未启用 ESAppender 时不会集中打印附加日志。
自定义 Appender 和 FileAppender 仍接收采集时的原始附加日志。

## 数值显示精度

日志中带小数部分的数值四舍五入到两位小数（例如普通数值 `244747.43`），包括
结构化字典、JSON、数组、附加状态及运行指标日志。整数计数、错误码、时间戳、布尔值
保持原样；浮点类型的整数值也不补小数（例如 `795428.0` 显示为 `795428`）。
不通过 Double 转换大整数。普通字符串与 URL 不做数字正则替换。
statLogs 在序列化时保留最多两位小数；JSON 数字不会强制补零。
采样、计时、累计和业务统计回调保留原始精度，仅日志展示/上传样本进行舍入。

### 播放汇总日志

播放统计按 vplayer 的用途拆分为 `playtime`、`StalledSummaryInfoStatistics.summarize` 和 `playerCreation`，
不再输出包含 session/source/attempt 和 metrics 的整包 `playback_statistics:`。
完整业务快照保持兼容；触发条件、单位及累计口径见 [播放统计](PlaybackStatistics.md)。

### 运行指标日志的单位

`runtime metrics:` 文本按量级显示单位：bandwidth 使用 bps/Kbps/Mbps（1000 进制）；
net_bytes/read_bytes 及其 total 使用 B/KiB/MiB（1024 进制）；net_speed/read_speed 使用对应字节单位每秒。
帧率使用 fps，丢帧使用“帧”，丢包使用“包”，请求数使用“次”。
例如 `bandwidth=19.49Mbps net_bytes=1.46MiB net_speed=461.19KiB/s`。
单位换算仅用于日志文本；statLogs、metrics 和业务回调仍使用原始数值和既有单位。
