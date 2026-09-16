# iOS 业务接入指南

## 交付范围

MediaPlayerKit 是原生视频 SDK，支持通过 Swift 或 WKWebView JS 调用。当前交付准备针对 iOS 14+；HLS、HTTP-FLV、RTMP 和具体视频编码须以随包验收结果为准。SDK 的其他平台声明不代表本交付已验收。

正式包应给出精确 Xcode/Swift 版本、SDK 构建版本及依赖清单。完整版本形如 `1.0.0+20260910183000(UTC+8).abcdef123456.218`；日期是北京时间。CFBundleShortVersionString 仍为三段版本。

## 安装二进制

1. 将 SDK 目录中所有已确认需要的 XCFramework 加入业务 Target。
2. 动态 framework 选择 Embed & Sign；静态库只链接、不嵌入。交付方必须在检查报告中说明各依赖的类型，不可统一勾选嵌入。
3. 保留 framework 自带资源；独立 .bundle 按资源加入 App。不要只复制 framework 中的可执行文件。
4. `import MediaPlayerKit` 应在无 SDK 源码的空工程中成功编译并链接。若提示缺少 KSPlayer/FFmpeg 等模块，说明交付依赖不完整，应由交付方修复，不能要求业务猜测依赖版本。
5. `vzplayer-bridge.js` 必须可通过 SDK 的 PlayerBridge.installJavaScript 加载。

SDK 当前依赖 KSPlayer 2.3.4、FFmpegKit 6.1.4，精确 revision 见 Package.resolved。这只是构建依赖信息，不代表二进制只需要这两个文件；实际框架、Swift 模块、资源和底层库以产物检查报告为准。

## 初始化与原生播放

App 在主线程初始化一次；不要每次切换播放地址都重新初始化：

```swift
import MediaPlayerKit
let options = InitConfig()
options.userId = 10001
options.topicId = "business-player"
options.appenders = ["ConsoleAppender"]
export.Init(options, "{\"env\":\"prod\"}")
```

创建 MediaPlayerView 并由业务设置布局。页面强引用播放器：

```swift
let player = export.CreateVZPlayer(playerView)
player.setSources([PlayerSource(url: playbackURL, type: "hls", isLive: true)])
player.play()
```

用 SetOnH5EventListener 接收状态。监听器由业务强引用。播放、源切换和视图操作在主线程调用。SDK 不负责业务鉴权、获取播放地址或节点调度；这些由 App 提供。

## H5 混合接入

原生 MediaPlayerView 渲染视频，WKWebView 展示控制界面，业务自行布局二者。不是 HTML video 播放，也不会自动跟踪网页元素的位置。

```swift
let content = WKUserContentController()
try PlayerBridge.installJavaScript(in: content)
let bridge = PlayerBridge(player: player)
content.add(bridge, name: "vzPlayerBridge")
let configuration = WKWebViewConfiguration()
configuration.userContentController = content
let webView = WKWebView(frame: .zero, configuration: configuration)
bridge.webView = webView
```

页面必须强引用 player、bridge、webView；在安装脚本及处理器后再加载 H5。bridge 内部 player/webView 是弱引用。不要再注册第二个播放器事件监听器覆盖 bridge 的监听器；需要业务事件时采用统一协调器。

```javascript
window.vzPlayerBridge.onEvent = event => console.log(event);
window.vzPlayerBridge.onTimeUpdate = seconds => console.log(seconds);
await window.vzPlayerBridge.request('play');
await window.vzPlayerBridge.request('setVolume', {volume: 0.5});
```

Demo 的 `loadURL` 是业务扩展，不是 SDK 标准方法。H5 输入地址时，App 的处理器校验地址、构造 PlayerSource、调用 setSources/play，再用 PlayerBridge.reply 返回结果。参考仓库 H5URLPlayerView.swift；该 Demo 页面不依赖节点 API。

仅把播放器桥接注入可信业务页面；处理器及页面导航来源由宿主控制。HTTPS 优先；确实需要 HTTP 时由业务配置适用的 ATS 策略，不要求全局放开网络限制。

## 生命周期

页面退出：停止 WebView 加载，移除 vzPlayerBridge 消息处理器，调用 player.destroy()，清空桥接引用并释放对象。不要在单个页面退出时调用全局 Logger.destroy()。进入后台、音频会话、后台播放权限及横竖屏策略由业务结合场景管理，本交付不承诺后台持续播放。

## 日志与排障

先使用 ConsoleAppender 验证。文件日志通过 InitConfig.fileAppenderPath 配置可写路径；服务端上传还需日志服务地址和鉴权配置，交付包不包含生产密钥。export.lastLoggingError 用于检查初始化问题。上传记录 version 使用完整 SDK 构建版本。

反馈问题时提供完整 SDK/Demo 版本、设备和 iOS 版本、复现步骤、失败前后的日志、期望行为、是否可稳定复现。鉴权地址或日志中的敏感信息通过双方约定的私密渠道提供。

源码参考：Sources/MediaPlayerKit/VZPlayer/{export,IH5Player,PlayerBridge}.swift；详细日志配置见随包 Logging.md。


## 默认桥接的绑定与安全边界

以下操作在主线程进行。业务自定义桥接仍可直接调用 `IH5Player`，无需创建 PlayerBridge 或注入 SDK JS。

- `PlayerBridge(player:)` 维持原有行为：创建时注册 H5 事件监听器。
- 更换默认桥接所服务的播放器，使用 `bridge.bind(player: newPlayer)`，显式绑定新播放器的事件。
- 直接赋值 `bridge.player` 保持命令分发用途，不自动占用新播放器的监听器，兼容已有自定义处理器。
- `bridge.detach()` 清空桥接引用；对 SDK H5Player，只在监听器仍属于当前桥接时解绑，避免清除业务后来安装的监听器。对第三方 IH5Player 实现，监听解绑仍由该实现/宿主负责。
- detach 不销毁播放器，不移除宿主注册的 WKScriptMessageHandler。退出页面时仍需宿主移除处理器，并按播放器所有权决定是否调用 destroy。

默认消息入口仅接受绑定 WebView 的主 frame。设置宿主允许的页面，例如：

```swift
bridge.allowsPage = { url in
    url.scheme == "https" && url.host == "player.example.com"
}
```

业务需要通过 WKNavigationDelegate 同时限制页面导航；在开始导航时调用 `bridge.invalidatePage()`，使等待中的旧回调失效并暂停派发，在 `didCommit` 调用 `bridge.commitPage()` 后，才允许新文档重新握手。SDK 不接管宿主的 navigationDelegate。未设置 allowsPage 时，SDK 不替业务猜测域名白名单；仅加载可信业务页面。

H5 先注册监听，再调用 `await window.vzPlayerBridge.ready()` 恢复当前状态。原有事件名、错误通知语义及播放源由原生设置的接入模式均不变。


导航代理示意（多次快速导航时应像 Demo 一样核对 WKNavigation 身份）：

```swift
func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    bridge.invalidatePage()
}
func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    bridge.commitPage()
}
```

若当前导航在提交前失败、宿主明确保留旧页面，可调用 commitPage 重新连接；旧导航的取消回调不可恢复新的导航。SDK 不自动接管 navigationDelegate。

自定义指令采用统一入口：

```swift
bridge.handleMessage(message) { method, paramsJson in
    guard method == "loadURL" else { return nil } // nil 交回 SDK 标准分发
    return loadValidatedURL(paramsJson) // 返回 ["ok": true, "result": ...] 或错误
}
```

业务处理器负责参数校验；SDK 负责执行前的页面、来源、播放器存活检查，并填入 requestId/pageId 后发送回执。处理器按同步指令受理返回，不代表网络播放完成。
