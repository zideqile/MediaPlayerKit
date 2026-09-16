# 播放统计与 vplayer 对标

## 数据入口

- Native：实现 `PlayerEventListener.onStatistics(_:)`，通过 `AddEventListener` 注册。
- IH5Player：实现 `H5EventListener.onStatistics(_:)`；`get_statistics?()` 获取最近一次 JSON 快照。
- JS：`vzPlayerBridge.onStatistics = data => { ... }`；或 `await vzPlayerBridge.request('getStatistics')`。
  这是 MediaPlayerKit 新增接口，Android 端需有同名能力才可直接调用。
- 全局观察：`PlayerStatisticsEvents.didUpdate`，通知的 `userInfo` 是同一快照。按 `sessionId` 区分播放器。
- 当前容器：`MediaPlayerView.playbackStatistics`；原生多源门面：`MultiSourcePlayer.currentStatistics`。
- SDK 日志：按用途拆分的播放时长、卡顿汇总和创建统计日志，复用现有分组、等级过滤、ES 上传与 Demo SDK 日志面板。
  业务回调不依赖日志级别。现有 Android 对标 statLogs 指标保留。

Native 回调和通知在主线程异步交付，避免业务回调重入切源过程；每条记录含自身的源与会话标识，
收到旧记录不表示播放器仍在该源上。不要同时消费通知和 listener 后重复累计同一条记录。
销毁时结算最终统计，停止定时器；H5 已关闭后不保证 JS 能收到最终记录，应以 Native/日志为准。

## 归属与口径

`sessionId`：每次显式 setSources 开始新会话，切源、内核降级及恢复仍属于该会话。
`sourceId`：连续使用一个源的阶段，切到别的源再回来会生成新 ID。
`attemptId`：一次内核尝试，每次创建替换内核都会生成新 ID。

`session`、`source`、`attempt` 是各层累计量：

| 字段 | 口径 |
| --- | --- |
| play_ms | 只累计 playing 状态的单调时钟时长，暂停、卡顿及恢复间隙不计入 |
| stalledTotalDuration | buffering 状态累计毫秒；暂停、错误、切源或销毁会结算未结束的区间 |
| stalledCount | 进入 buffering 的次数，重复通知不重复计数，包含起播阶段 buffering |
| stall_ratio | 卡顿时长 /（有效播放时长 + 卡顿时长），排除暂停时间 |

`window` 为自上一次快照以来的增量，不是固定自然时间窗口。
`sequence` 是实例内递增序号；后台应以 sessionId + sequence 去重。
累计量按相应 ID 覆盖更新，不能逐条相加；需要求和时只累加去重后的 window。
跨窗口卡顿的时长逐段计算，次数只在开始所在区间增加。

`create_ms` 是从开始本次尝试到 MediaPlayerController 对象创建完成的耗时，
`createOK` 不表示媒体已可播放。`first_frame_time` 是本次尝试开始至首帧通知的耗时。

会话还包含 attempts、source_switches、engine_switches、errors，
以及 recoveries、recover_ok、recover_fail、recover_cancel。
同一连续自动恢复过程只计一次；内核报告 playing 时判为恢复成功，最终失败计失败，
用户切源/替换源列表/销毁打断未完成恢复计取消。recover_ms 为最近已结算恢复耗时。

## 采集与发布

`generalStatisticsUploadInterval` 与 vplayer 使用相同单位：毫秒，默认 10000。
0 关闭周期快照，但保留创建、首帧、恢复、错误、切换及销毁等事件快照。
该参数控制统计记录生成，ES 实际发送节奏仍由 logConfig.uploadIntervalSeconds 控制。

### 按 vplayer 的统计用途拆分日志

完整快照继续供 Native、JS 和 Demo 使用，字段及 schemaVersion 保持兼容；不再整包写入 `playback_statistics:`。

| 日志 | 触发与字段 |
| --- | --- |
| `StalledSummaryInfoStatistics.summarize` | 窗口存在卡顿次数或时长时输出 error 日志；沿用 vplayer 的 `stalledCount`、`stalledTotalDuration`（毫秒） |
| `playerCreation` | 创建完成时输出 `elapsed`（带 ms 单位）、`createOK` |
| `playtime` | 关键动作与事件（暂停、跳转、停止、卡顿、恢复、播放结束、切源、重试错误等）及尝试/会话结束时，结算并输出各类维度（attempt 内核+地址、source 当前地址、session 当前会话）的累计时长；实例销毁输出 lifetime 总时长和 attempts |

`playtime.totalPlayTime` 日志值以秒为单位（带 s 后缀，例如 `5s`、`112.50s`）；`scope` 区分 attempt/source/session/lifetime，`reason` 标识结算原因。
不同 scope 有包含关系，不能混合相加。
新增关键动作与事件实时结算，便于在会话进行中随时从日志检索各维度播放时长。
新增 `lifetime` 快照包含实例整个生命周期的时长、卡顿和 `attempts`（内部播放器尝试数，含失败尝试），
不随 setSources 重置；`session` 仍在 setSources 时重置。`attemptEnded` 表示本条快照是尝试最终结算。
实例销毁在原 sessionEnded:destroy 快照之后追加 lifetimeEnded 快照，重复销毁不重复输出。
这里的实例指一个 MultiSourcePlayer，不汇总 App 中多个独立播放器实例。
`stall_pct` 为附带 % 的百分比，例如 `0.06%`；业务快照中的 `stall_ratio` 仍为原始比例。
首帧、恢复与错误沿用已有专项日志；性能采样沿用 statLogs，不重复附带整份 metrics。

周期快照仍持续交付业务回调。平稳周期不产生上述汇总日志，但普通事件日志和 statLogs 仍可能上传。
`reportable` 保留原兼容语义，表示快照是否满足原日志候选条件，并不表示实际发生网络请求。
ES 实际发送仍由现有上传策略控制，本次没有增加独立上报接口。

这是按用途对标，并非逐字复刻 vplayer 的上传协议：vplayer 的独立播放时长上传调用目前被注释；
原生卡顿会跨窗口分段结算，并在切源、错误或销毁时保留未结束区间，避免遗漏时长。

运行状态与可用性能指标按 runtimeStateCollect.collectIntervalSeconds 采样，默认 3 秒。
定时采样不依赖进度回调，卡顿时仍工作；metrics_time 标识 metrics 最后采样时刻。
内核和源切换时清空旧性能样本，避免跨内核累计计数器相减。

## 原生能力边界

metrics 只包含内核实际返回的有效指标：显示帧率（`fps`）、标称帧率（`frame_rate`）、观测吞吐率（`bandwidth`）、网络增量与速率（`net_bytes`、`net_speed`、`net_bytes_total`）、读取增量与速率（`read_bytes`、`read_speed`、`read_bytes_total`）、丢帧与丢包（`drop`、`drop_count`、`drop_packet`、`drop_packet_count`）以及媒体请求（`media_requests`、`media_requests_total`）。所有字段除既有对标字段外均遵循言简意赅原则，首次采样和计数器重置后不伪造差值。

### 请求统计

SDK 通过真实请求事件生成以下 error 级别汇总，复用 ES 和 Demo SDK 日志：

| 日志后缀（前缀均为 `PlayerSourceRequestStatistics.`） | 内容 |
| --- | --- |
| `logSlowRequests` | 超过 `slowRequestThreshold` 的请求；默认 600ms，沿用 url/endAt/elapsed/size，未知字段省略 |
| `logAbnormalRequests` | 按 URL 统计重复访问，排除 playlist 类型和 URL 路径以 .m3u8 结尾的请求（忽略大小写、查询参数和片段）；沿用 count/startAt，这不是“访问必然失败”的判定 |
| `logUnexpectedStatusRequests` | 实际 HTTP 4xx/5xx；保留 url/status/endAt |
| `logNetworkErrors` | 有错误码但无可信 HTTP 状态的事件，使用 code/domain，属于原生扩展 |

包络沿用 playerInstance/sourceType/sourceUrl/sourceDomain/requestInfo；kind 区分 playlist/segment/key。
`elapsed`、`endAt`、`startAt` 为毫秒，size 为最后一次网络事务实际收到的响应正文大小（字节），
不是整条流的大小；小数格式使用现有日志规则，业务事件保留原精度。

支持范围：
- Xcode 16/Swift 6 及以上编译，iOS/tvOS 18、macOS 15、visionOS 2 及以上运行：
  AVPlayer 订阅 HLS playlist/segment/key 的 AVMetrics，`request_scope=hlsRequests`、`request_details=true`。
  此标记表示 HLS 明细接口可用，不保证系统为每次请求提供全部字段；非 HLS 源不宣称明细能力。
- 旧系统或旧编译器：AVPlayer 采集 errorLog，`request_scope=errorLog`、`request_details=false`。
  错误码携带其原始 domain，不直接当作 HTTP 状态，也不推算请求耗时或次数。
- 当前 KSPlayer/FFmpeg：`request_scope=engineAggregate`、`request_details=false`。
  上游公开接口没有完整逐请求生命周期回调，尚未接入慢请求或重复请求自动采集。
  保留统一的 PlayerRequestEvent / MediaPlayerProtocol.requestEventHandler 扩展入口，不能将此视为 KS 已支持。

周期沿用 generalStatisticsUploadInterval；0 关闭周期汇总，切换、错误、重设源和销毁仍提交已收到的记录。
异步请求事件按控制器实例隔离；旧播放器停用后到达的事件丢弃，未完成/未交付事件不伪造结算。
慢请求和异常状态各保留最近 5 条；重复 URL 检测缓存直播 10 个、点播 100 个，
汇总最多 100 个 URL、每个 URL 最多 30 个时间样本，count 为窗口内纳入的次数，可能大于时间样本数。
重复汇总不会在下个窗口再次计入第一次访问；切源时清空检测缓存。

与 vplayer 的区别：206/304 等有效响应不当作异常；缓存命中不算网络请求；
按完成事件回填实际开始时间，统计受缓存上限约束；播放列表重复加载不计异常，但慢请求和 HTTP 错误仍统计；其余重复 URL 仍可能来自正常 Range 请求。
没有通过重发探测请求、修改媒体地址或代理下载来生成数据。

接口依据：[Apple AVMetrics 介绍](https://developer.apple.com/videos/play/wwdc2024/10113/)、
[资源请求事件](https://developer.apple.com/documentation/avfoundation/avmetricmediaresourcerequestevent)、
[错误事件](https://developer.apple.com/documentation/avfoundation/avplayeritemerrorlogevent)。

PlayerQoSReport 的 DNS、TCP、首包、未到达的首帧默认值改为 NaN，未采集的 droppedFrames 为 -1；
对外 Swift/Objective-C 属性类型保持不变。toDictionary 将这些未采集值输出为 JSON null，
实测的 0 则保留为 0。分辨率、硬件加速状态没有依据时也输出 null。
直接读取属性的业务代码应检查 isFinite / 非负值，不应把占位值当有效测量。

原生 QoSAPMTracker 采用同一状态计时器；snapshot 为非终止读取，finish 幂等结算。
Demo QoS 页面已移除固定示例数值，展示最近收到的真实会话快照；没有数据时明确显示未采集。


## 字段命名与版本 2

JSON/日志中的自定义字段使用简短名称；vplayer/vzplayer 已有字段保持原名。
Native 的 Swift/Objective-C 属性名不变。本次快照和 PlayerQoSReport.toDictionary 的
schemaVersion 为 2，不同时输出旧别名，业务侧需按版本更新读取字段。
first_frame_time 沿用 Android 既有名称，单位毫秒；play_ms/create_ms/recover_ms 为毫秒，
play_sec/stall_sec 为秒，metrics_time 为 Unix 毫秒时间戳。

bandwidth 是 AVPlayer 观测下载吞吐率（bit/s），不是视频编码码率。
net_speed 为本采样周期网络字节增量除以单调时钟间隔（B/s），两者统计区间不同，
不能简单按 8 倍换算后要求相等。net_bytes/media_requests 为周期增量，_total 后缀为累计值。

| 旧字段 | 新字段 |
| --- | --- |
| `playDurationMs` | `play_ms` |
| `stallRatio` | `stall_ratio` |
| `attemptCount` | `attempts` |
| `sourceSwitchCount` | `source_switches` |
| `engineSwitchCount` | `engine_switches` |
| `errorCount` | `errors` |
| `recoveryCount` | `recoveries` |
| `recoverySuccessCount` | `recover_ok` |
| `recoveryFailureCount` | `recover_fail` |
| `recoveryCancelledCount` | `recover_cancel` |
| `recoveryDurationMs` | `recover_ms` |
| `firstFrameDurationMs` | `first_frame_time` |
| `creationDurationMs` | `create_ms` |
| `metricsSampleTime` | `metrics_time` |
| `requestMetricsScope` | `request_scope` |
| `requestDetailsAvailable` | `request_details` |
| `dns_duration_ms` | `dns_ms` |
| `tcp_duration_ms` | `tcp_ms` |
| `first_packet_duration_ms` | `first_packet_ms` |
| `first_frame_duration_ms` | `first_frame_time` |
| `play_duration_sec` | `play_sec` |
| `stutter_duration_sec` | `stall_sec` |
| `bitrate`（原 observedBitrate） | `bandwidth` |

## 起播、缓冲和进度停滞保护

MultiSourcePlayer（包括 H5 混合接入）新增主线程独立定时检查，约每 500ms 检查一次，
不依赖内核报错或进度回调。配置可通过 VPlayerConfig 或其 JSON 传入：

| 配置 | 默认值 | 含义 |
| --- | --- | --- |
| startupTimeoutMs | 15000 | 每次内部播放器尝试起播，尚无首帧或有效播放进度时的超时 |
| bufferingTimeoutMs | 15000 | 已起播后的持续缓冲，或 playing 状态下播放进度持续不动的超时 |

单位毫秒，值 <= 0 关闭相应检测。阈值是 SDK 默认值，并非 vplayer 原有配置名或默认值。
使用单调时钟；用户暂停、App 非活跃期间不累计，恢复后重新给予完整等待预算。
Seek 发起时重置等待预算；自然播放结束、替换源列表、切换、终止失败和销毁时取消旧检测。
重播可通过进度推进结束起播等待，不要求内核再次发出首帧事件。

超时生成 NSURLErrorTimedOut，附带 phase（startup/buffering/frozen）和 timeout_ms，
复用 onPlayAttemptFailed、onRecoveryStarted、failureHistory 及既有失败日志。
有后备内核时先切内核，再切下一个地址；候选耗尽后发出最终错误，不循环重试。
每次尝试只处理一次失败，generation 和控制器身份阻止旧定时器操作新的播放源。
此保护属于 MultiSourcePlayer 的恢复层，不修改 KSPlayer/FFmpeg 底层采集或网络参数；
单独使用 MediaPlayerController 不带多源恢复策略。

与 vplayer 对照：FreezeDetector 检查进度冻结、暂停/后台豁免的思路相同；
vplayer 每 8 秒检测，直播/点播起始宽限分别为 8/16 秒，普通冻结请求 restart，
H.265 或 24 秒内反复冻结请求 switchNextSource。SDK 本次继续使用自身的内核/地址候选顺序。
vplayer 另有默认关闭、只用于直播的滑动窗口卡顿策略（默认 60 秒内超过 6 秒或 3 次，
忽略小于 200ms 的卡顿），SDK 通过下面的同名策略提供这项能力。


## 直播滑动窗口卡顿策略

`stalledSourceSwitchPolicy` 与 vplayer 同名，默认配置：

```json
{
  "isLive": true,
  "stalledSourceSwitchPolicy": {
    "enable": false,
    "slidingWindowInMs": 60000,
    "maxStalledDurationInMsInSlidingWindowInMs": 6000,
    "maxStalledCountInSlidingWindowInMs": 3,
    "minStalledDurationThreshold": 200
  }
}
```

业务需将 enable 设为 true 才启用；点播不启用。各数值配置 <= 0 时使用对应默认值。
buffering → playing 结算一次完整卡顿；小于 200ms 忽略，重复 buffering 通知不重置开始时间。
以卡顿结束时间判断是否在窗口内，在下一次进入 buffering 时检查：累计时长严格大于 6000ms，
或次数严格大于 3 次时触发；恰好等于阈值不触发。超长单次未结束缓冲仍由独立 watchdog 处理。

触发后记录 `StallDetector.onWaiting`，沿用 vplayer 的字段：
`stalledDurationInMsInSlidingWindowInMs`、`stalledCountInSlidingWindowInMs`、
`totalStalledDuration`、`totalStalledCount`。累计字段归属于当前内部播放器尝试。
恢复错误分类新增 `stalled`（追加枚举值，既有值不变），错误 domain 为 MediaPlayerKit.Stall、code 为 1。
通过既有失败/恢复事件链直接尝试下一地址，不先换内核；没有下一地址时结束恢复并报告错误。
同一尝试只处理一次失败，与 watchdog 或内核错误共享防重复和旧任务隔离保护。

暂停、后台、Seek 期间不采集新的卡顿，丢弃跨越这些操作的未完成区间；已经结算的样本按窗口自然过期。
Seek 完成回调按控制器、播放 generation 和 seek generation 隔离，旧回调不影响新源。
切换、销毁或重设配置清空检测状态，不混合两个策略配置或两个内部播放器的样本。
这只影响恢复策略的卡顿样本，现有播放统计的累计口径不变。

watchdog 的过期 Timer 会主动 invalidate；仅当它仍是当前 Timer 时清空引用，避免误清理新任务。


### playtime 日志可读性

attempt 输出 sourceUrl 和实际 engine；source 输出 sourceUrl 和本源阶段实际尝试过的 engines（去重、保留尝试顺序）。
sourceId 标识同一 sourceIndex+URL 的连续使用阶段，切离再回来会生成新 ID，不是 URL 永久标识。
attemptId/sourceId/sessionId 仅日志显示 UUID 第一段，完整统计快照中的 ID 保持不变，可靠关联和去重使用完整 ID。
各层 totalPlayTime 统一使用秒（例如 112.50s），stall_pct 直接显示百分比（例如 0.10%）。
卡顿占比为卡顿时长 /（播放时长 + 卡顿时长）；0.10% 表示千分之一。未知时长保留 null。
原始快照 play_ms（毫秒）与 stall_ratio（比例）不变，新增 sourceEngines 表示当前源阶段的内核历史。
