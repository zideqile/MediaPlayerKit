# 日志模块对标说明

实现位置：`Sources/MediaPlayerKit/VZLogger`。参考 Android `vzlogger/src/main/java/vzlogger`。
本模块尚未接入 `export.Init`、播放器、引擎、H5 Bridge、QoS 或 Demo。必须由使用方显式启用。

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

## 显式使用示例（尚未放进任何 SDK 流程）

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

`ESAppender` 使用 `appVZPlayerConfigJsonString` 的 forceUseNewESUploader（默认 true）、statLogIsAttachedToLog（默认 false）、statsMinUploadIntervalMs（默认 180000）。有鉴权回调且允许新协议时选新协议，否则选旧协议。`FileAppender` 使用 InitConfig.fileAppenderPath。

## 生命周期与边界

- initialize 只配置工厂；不取远程配置，不创建播放器，不立即发送请求。首次创建组才创建输出器和定时器。
- configure/initialize 会销毁上次配置及旧 Logger；调用方应重新获取分组。
- 工厂产生的 Appender 由 Logger 销毁且按对象去重；addAppender 添加的外部对象由调用方销毁，移除不会关闭共享对象。
- 自定义 Appender/transport 回调应快速返回，不要同步反调 Logger，避免跨串行队列等待。网络使用异步 URLSession。
- flush 表示封装并排队，**不代表服务器已收到**。destroy 立即停止后续工作并丢弃排队记录，已提交请求可能完成；flush 后立即 destroy 不能保证送达。
- 切源先封装旧源记录，再更新源信息。上传记录不受后续修改 VPlayerConfig 的影响。
- 上传默认最多 1000 条缓冲普通日志、30 条附加日志、100 个统计名称及每项最近 30 个值；消息截断至约 8 KiB。队列最多 10 条待上传记录，另加 1 个在途请求。容量溢出计入 innerDrop（附加日志/统计滚动窗口正常淘汰除外）。
- 分块目标约 10 KB；上下文及单条大消息可能超过目标，不承诺硬上限。文件为追加模式，尚无轮转/磁盘配额。
- 相似度沿用 Android 字符串编辑距离与数字相对差；字符串超过 2048 字符只做精确匹配，避免耗时过大。
- 尚未移植 Android 的远程调试配置获取、ASM 自动位置注入、业务埋点常量和播放器统计采集。这里提供日志基础设施，采集接入后续单独处理。

## 验证

`Tests/MediaPlayerKitTests/LoggingTests.swift` 使用假 transport/uploader，不访问真实服务器。
Linux 可通过独立临时 Swift Package 编译 VZLogger 文件，并仅在临时配置副本移除 `@objc` 属性运行测试；正式源码不做该转换。
完整 Apple 平台编译与真实日志服务联调仍需 Xcode/设备环境。
