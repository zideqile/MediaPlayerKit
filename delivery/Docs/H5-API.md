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
