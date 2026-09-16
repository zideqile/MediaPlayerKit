# H5 标准接口

调用：`await window.vzPlayerBridge.request(method, params)`。params 默认为对象 {}，SDK 会编码 JSON。iOS 通过 requestId 关联回执，默认 10 秒超时，页面退出清理等待请求。

| 方法 | 参数 | 成功结果 |
| --- | --- | --- |
| play / pause / resume / destroy | {} | null，仅表示指令受理 |
| getCurrentTime / getDuration | {} | {currentTime: 秒} / {duration: 秒} |
| setCurrentTime | {currentTime: 非负秒数} | true |
| getPause | {} | {pause: boolean} |
| getVolume / setVolume | {} / {volume: 0...1} | {volume: number} / true |
| getMuted / setMuted | {} / {muted: boolean} | {muted: boolean} / true |
| getLoop / setLoop | {} / {loop: boolean} | {loop: boolean} / true |
| getSpeed / setSpeed | {} / {speed: 正数} | {speed: number} / true |
| getVideoWidth / getVideoHeight | {} | {videoWidth: number} / {videoHeight: number} |
| getBuffered | {} | {length, start, end} |
| getCurrentSource | {} | 当前源对象；没有源时 {} |
| switchSource | {index: 当前列表中的索引} | true |
| SendEvent | {eventName: "NEXT_SOURCE", params: {}} | true，仅表示受理 |

setSources 不在标准 JS 接口中；由 App 设置播放源。指定索引切换也可用 SendEvent 的 SWITCH_SOURCE 及 params.index，此为 iOS 扩展。

失败会 reject；错误包括 unsupported_method、player_unavailable、invalid_parameters_or_rejected、bridge_timeout、page_closed。拒绝参数不会改变原 setter 状态。播放器后续失败通过事件通知，不通过已完成的请求 Promise 返回。

事件：window.vzPlayerBridge.onEvent(name)，常见为 play、canplaythrough、playing、pause、waiting、ended、recovering、PlayerWARN。canplaythrough 为就绪，不能当成已经播放；playing 才表示播放状态。最终播放错误通过 PlayerWARN，中间恢复不会误报为最终失败。

进度：onTimeUpdate(seconds)。onError(code,message) 是保留回调，不能只依赖它判断最终失败。

Android：普通方法由 JS 适配包装对象 AndroidBridge 或 vzPlayerNative。SendEvent 的 Java 枚举调用需宿主配置 androidSendEvent；未配置返回 android_event_adapter_required。Android 当前枚举是 NEXT_SOURCE / SWITCH_PLAYER，不承诺支持 iOS 的 SWITCH_SOURCE；iOS 不支持 SWITCH_PLAYER。

旧版无 requestId 的 postMessage 仍可发送，但没有标准请求回执。业务不要把 Demo 自定义节点调度命令当成 SDK 接口。


## 默认桥接的页面与生命周期管理（iOS 扩展）

原有方法名、返回格式和 `PlayerWARN` 语义保持不变。Android 原生调用分支不发送新增握手，不要求 Android 实现新增方法。

SDK JS 为每个文档生成独立 `pageId`，自动通知默认桥接；请求编号也包含该标识。默认桥接确认消息来自当前 WebView 的主 frame 和当前文档，再执行指令。事件与回执携带/校验文档标识，避免刷新后的新页面接收旧页面消息。

H5 注册回调后显式同步一次当前状态：

```javascript
const bridge = window.vzPlayerBridge;
bridge.onEvent = name => updatePlaybackUI(name);
bridge.onTimeUpdate = seconds => updateProgress(seconds);
const state = await bridge.ready();
// iOS 返回当前属性、source、statistics，以及最近的 event；不是事件历史重放。
// Android 返回 null，继续使用业务已有的初始化/状态同步协议。
if (state) renderCurrentState(state);
```

`ready()` 对应 iOS `bridgeReady`，返回 `event`、`currentTime`、`duration`、`pause`、`volume`、`muted`、`loop`、`speed`、`source`、`statistics`、`destroyed`。首次尚无事件时 `event` 为空字符串。页面隐藏会拒绝未完成请求，恢复显示后自动重新通知原生；业务在需要恢复 UI 时再次调用 `ready()`。早于监听注册的历史事件不逐条缓存，应使用快照恢复界面。

默认桥接销毁播放器后，后续请求拒绝为 `player_destroyed`；重复 destroy 保持幂等。此规则不修改 Android 销毁后可重建的原生行为。`bridge.detach()` 后请求拒绝为 `bridge_closed`。

旧版无 pageId 消息仍兼容，但不具备文档隔离保证。业务自定义处理器直接调用 `handleRequest`/`reply` 时，来源验证和页面隔离由业务负责；原样回传请求中的 `pageId` 可启用 reply 的页面校验。
