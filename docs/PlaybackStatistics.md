# 播放统计与 vplayer 对标

## 数据入口

- Native：实现 `PlayerEventListener.onStatistics(_:)`，通过 `AddEventListener` 注册。
- IH5Player：实现 `H5EventListener.onStatistics(_:)`；`get_statistics?()` 获取最近一次 JSON 快照。
- JS：`vzPlayerBridge.onStatistics = data => { ... }`；或 `await vzPlayerBridge.request('getStatistics')`。
  这是 MediaPlayerKit 新增接口，Android 端需有同名能力才可直接调用。
- 全局观察：`PlayerStatisticsEvents.didUpdate`，通知的 `userInfo` 是同一快照。按 `sessionId` 区分播放器。
- 当前容器：`MediaPlayerView.playbackStatistics`；原生多源门面：`MultiSourcePlayer.currentStatistics`。
- SDK 日志：独立普通日志 `playback_statistics:`，复用现有分组、等级过滤、ES 上传与 Demo SDK 日志面板。
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
| playDurationMs | 只累计 playing 状态的单调时钟时长，暂停、卡顿及恢复间隙不计入 |
| stalledTotalDuration | buffering 状态累计毫秒；暂停、错误、切源或销毁会结算未结束的区间 |
| stalledCount | 进入 buffering 的次数，重复通知不重复计数，包含起播阶段 buffering |
| stallRatio | 卡顿时长 /（有效播放时长 + 卡顿时长），排除暂停时间 |

`window` 为自上一次快照以来的增量，不是固定自然时间窗口。
`sequence` 是实例内递增序号；后台应以 sessionId + sequence 去重。
累计量按相应 ID 覆盖更新，不能逐条相加；需要求和时只累加去重后的 window。
跨窗口卡顿的时长逐段计算，次数只在开始所在区间增加。

`creationDurationMs` 是从开始本次尝试到 MediaPlayerController 对象创建完成的耗时，
`createOK` 不表示媒体已可播放。`firstFrameDurationMs` 是本次尝试开始至首帧通知的耗时。

会话还包含 attemptCount、sourceSwitchCount、engineSwitchCount、errorCount，
以及 recoveryCount、recoverySuccessCount、recoveryFailureCount、recoveryCancelledCount。
同一连续自动恢复过程只计一次；内核报告 playing 时判为恢复成功，最终失败计失败，
用户切源/替换源列表/销毁打断未完成恢复计取消。recoveryDurationMs 为最近已结算恢复耗时。

## 采集与发布

`generalStatisticsUploadInterval` 与 vplayer 使用相同单位：毫秒，默认 10000。
0 关闭周期快照，但保留创建、首帧、恢复、错误、切换及销毁等事件快照。
该参数控制统计记录生成，ES 实际发送节奏仍由 logConfig.uploadIntervalSeconds 控制。

### 静默优先与非必要不上报（对标 vplayer）

严格遵循 vplayer `StalledSummaryInfoStatistics` 的“非必要不上报”设计哲学，将**内存状态刷新**与**日志/网络上报**彻底解耦：
- **内存快照（持续供给）**：周期到达时始终更新内存快照 `latest`，触发 `onStatistics` 代理与 `PlayerStatisticsEvents.didUpdate` 通知，供本地 UI/大盘和 JS Bridge（`get_statistics`）随时零开销读取；
- **上报门禁（`reportable` / `isReportable`）**：只有满足以下条件时，才向 Logger 写入 `playback_statistics:` 并触发 ES 上传：
  1. **关键里程碑**：`created`、`firstFrame`、`error`、`recovered`、`ended`、`sourceEnded`、`sessionEnded:*` 等非周期性事件；
  2. **周期性检查（`periodic`）**：严格对标 vplayer，**仅当该周期窗口内发生卡顿（`stalledCount > 0` 或 `stalledTotalDuration > 0`）时才输出日志上报**。若该窗口内平稳播放且零卡顿，坚决不写 Logger、不上报 ES，实现平稳期零日志打扰、零网络开销。

运行状态与可用性能指标按 runtimeStateCollect.collectIntervalSeconds 采样，默认 3 秒。
定时采样不依赖进度回调，卡顿时仍工作；metricsSampleTime 标识 metrics 最后采样时刻。
内核和源切换时清空旧性能样本，避免跨内核累计计数器相减。

## 原生能力边界

metrics 只包含内核实际返回的值：显示/标称帧率、观测码率、可用字节、请求和丢帧计数，
以及采样周期差值与每秒速率。带 Total 的字段为本次内核提供的累计计数；delta/per_second
字段是最近采样区间的值，首次采样和计数器重置后不伪造差值。

requestMetricsScope 固定为 engineAggregate，requestDetailsAvailable 为 false。
AVPlayer access log 的汇总数据不能充当每个 m3u8/TS 请求的 URL、耗时、大小和 HTTP 状态。
本次未改造 FFmpeg 网络层、未增加代理，也未伪造慢请求/重复请求明细。
这些逐请求指标仍需底层提供可靠回调后单独扩展。

PlayerQoSReport 的 DNS、TCP、首包、未到达的首帧默认值改为 NaN，未采集的 droppedFrames 为 -1；
对外 Swift/Objective-C 属性类型保持不变。toDictionary 将这些未采集值输出为 JSON null，
实测的 0 则保留为 0。分辨率、硬件加速状态没有依据时也输出 null。
直接读取属性的业务代码应检查 isFinite / 非负值，不应把占位值当有效测量。

原生 QoSAPMTracker 采用同一状态计时器；snapshot 为非终止读取，finish 幂等结算。
Demo QoS 页面已移除固定示例数值，展示最近收到的真实会话快照；没有数据时明确显示未采集。
