# Demo 全屏与内核标识

iOS 的短视频、原生播放器、H5 混合和 H5 地址输入页共用 `DemoPlayerSurface`。
视频区域显示实际创建的 `AVPlayer` 或 `KSPlayer / FFmpeg`；未创建内核时显示“未创建”。
标识读取 `MediaPlayerView.currentEngineName`，跟随切源、自动降级和内核替换刷新，不根据 URL 猜测。

全屏按钮将包含 SDK 外层 MediaPlayerView 和控制按钮的完整容器移入当前 UIWindow 的覆盖层。
不创建播放器、不调用 play/stop，也不弹出新的全屏 UIViewController，所以不会因全屏而触发
页面 onDisappear 中的播放器销毁。画面保持原有缩放模式，横竖屏随系统和设备方向变化，
不强制修改设备方向。退出全屏恢复原容器；切页或销毁视图时清理覆盖层。

SDK 的 KS 内核不再暴露自带的全屏/返回按钮，也不执行其重挂载和模态控制器切换。
业务端需要自行管理外层播放器容器的全屏布局。UIKit/AppKit 布局只更新仍属于当前容器的
渲染视图，并跳过相同尺寸，SwiftUI 包装器不再同步强制 layoutIfNeeded。

## 验收

需用新构建的 SDK 重新构建 Demo（旧二进制不包含 currentEngineName）。

- 在四个页面分别使用 AVPlayer 和 KS/FFmpeg 播放，确认都有全屏入口且内核标识正确。
- 每种内核连续进入/退出全屏 10 次，检查声音、进度、触摸响应和退出后的原始布局。
- 全屏中旋转设备、前后台切换；退出按钮应一直可访问，画面随窗口尺寸变化。
- 暂停状态进入全屏不应自动开始；短视频点击全屏/退出按钮不应触发点击画面的暂停动作。
- 切源或自动降级后确认实际内核标识变化；切页/销毁后不应遗留黑色覆盖层。
- iOS 测试 `PlayerViewLayoutTests` 检查异父视图不被原容器改尺寸、容器反复往返和内核标识刷新。

Linux 仅能执行 Swift 语法和工程配置检查，不能替代 iOS 构建、UIKit 测试与真机卡死回归。
