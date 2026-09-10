# 播放容错对标

本次将 MultiSourcePlayer 的错误处理拆为 `PlaybackErrorClassifier`（Foundation 错误分类）、`PlaybackErrorAdapters`（Apple / KSPlayer 适配）和 `PlaybackRecoveryPolicy`（纯恢复决策），H5Player 沿用同一调度链。直接使用 MediaPlayerController 的调用方仍自行决定如何恢复。

## 恢复规则

| 分类 | 默认决策 |
|---|---|
| 源不存在、无效地址 | 跳过当前地址剩余内核，换下一个地址；没有则终止 |
| 网络、超时、鉴权、解码、未知 | 尝试下一候选内核；内核耗尽后换地址；全部耗尽后终止 |
| 明确取消（NSURLErrorCancelled） | 终止，不继续尝试 |

普通源 AV → ME；H.265 源 ME → AV；FLV/RTMP/RTSP 只使用 ME。RTSP 与控制器现有的实际路由保持一致，避免重复创建 ME 却标成 AV。

分类使用错误域和错误码、NSUnderlyingErrorKey 以及明确的 HTTP 状态。AVPlayerItem 错误日志中的 HTTP 状态会补充到原 NSError.userInfo 中；KSPlayer 的底层 AVError 使用依赖中的枚举值识别。未知错误保守走候选回退，不根据描述中的 URL、数字 404 或 “decoder not found” 判断源不存在。

Apple 解码错误映射参考：[AVError.Code](https://developer.apple.com/documentation/avfoundation/averror-swift.struct/code/decodefailed)。未映射的引擎错误保留为 unknown，不复制 Android 专属错误码。

## 事件契约

1. 每次失败发送可选 `onPlayAttemptFailed(PlaybackAttemptFailure)`，包含原始 NSError、源索引、源地址、内核、分类及恢复动作。
2. 有候选时发送可选 `onRecoveryStarted`。H5 额外发送事件名 `recovering` 并停止进度心跳；后续由真实播放状态恢复心跳。
3. 不再透传可恢复尝试的 `.error` 状态。没有恢复候选时，原生按 `.error` 状态 → 最终 `onError` 的顺序通知一次。H5 门面将最终原生错误映射为 `onEvent("PlayerWARN")`，不调用 H5 `onError`；中间警告不映射为 PlayerWARN，自动恢复使用 recovering。空源等终态输入错误也沿用这一 H5 映射。
4. 每个尝试只处理一次错误，旧控制器和重复回调会被过滤。用户在回调中切源、设置新源列表或销毁，会让排队的旧恢复任务失效。

两个新监听方法均为 Objective-C optional，现有实现无需增加方法。MultiSourcePlayer 和 H5Player 提供只读 `failureHistory`；更换源列表或显式切源时清空，自动恢复期间保留。

原生 MultiSourcePlayer 与视图操作须在主线程调用；H5Player 门面继续使用现有主线程转发。自动回退在主线程下一次调度执行，避免无效地址列表触发递归创建。

## 行为边界

- `Play([])` 返回 false 并发送终态错误；销毁后 Play 返回 false。非空列表返回 true 表示接受播放请求，不保证最终成功。
- 暂停意图会传递到恢复后新建的内核。音量、静音、循环和倍速仍按原逻辑保留。
- 尚未新增点播进度恢复、断网等待、退避重试、首帧超时看门狗或卡顿阈值换源；这些属于后续增强，不假定 Android 已完整实现。
- 恢复事件仍通过现有回调和新可选回调发出；目前 PlaybackDiagnostics 已同步记录尝试失败、恢复动作和最终错误，日志输出不改变事件契约。
- HTTP 错误日志不一定包含状态码；没有可靠证据时分类为 unknown 并保留原始错误供业务诊断。

## 测试

PlaybackRecoveryTests 覆盖错误域区分、底层错误链、HTTP 分类、策略矩阵、无效地址连续换源、最终事件去重及回调中销毁。Apple 环境另验证 AVFoundation / KSPlayer 枚举映射。
Linux 临时包可直接执行纯策略测试（仅在临时副本移除 @objc），以及使用平台替身执行不创建媒体引擎的无效源调度测试。它不替代 Xcode 编译与真实源联调。
