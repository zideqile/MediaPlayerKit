# MediaPlayerKit (iOS)

> A modern, high-performance, and commercial-ready multimedia player SDK for iOS based on **KSPlayer**, **FFmpeg**, **VideoToolbox**, and **Metal**.

[![Platform](https://img.shields.io/badge/Platform-iOS%2014.0%2B-blue.svg)](https://developer.apple.com/ios/)
[![Language](https://img.shields.io/badge/Language-Swift%205.9%20%7C%20ObjC-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-LGPL%202.1%2B-green.svg)](LICENSE)
[![Rendering](https://img.shields.io/badge/Rendering-Metal%20Zero--Copy-purple.svg)](https://developer.apple.com/metal/)

---

## 🌟 核心特性

- 🚀 **现代渲染管线**：全面基于 **MetalKit (`MTKView`)**，直接通过 `IOSurface` 与 `CVPixelBuffer` 进行 GPU 显存级**零内存拷贝渲染**，彻底废弃老旧的 OpenGL ES。
- ⚡️ **极速秒开与短视频优化**：
  - **播放器实例池 (`PlayerPoolManager`)**：毫秒级实例复用，杜绝短视频滑动时的频繁 `alloc/dealloc` 与内存颠簸。
  - **本地预加载代理 (`LocalPreloadProxy`)**：支持静默预下载下一个视频的头部 GOP 与 LRU 本地缓存。
- 🎬 **原生画中画 (PiP)**：基于 `AVSampleBufferDisplayLayer` 与 `AVPictureInPictureController`，开箱即用支持 iOS 14+ 系统级画中画。
- 📊 **工业级 QoS 质量观测**：全链路打点 DNS 解析、TCP 建连、首包到达、首帧渲染耗时、卡顿次数与硬解丢帧率。
- 🔒 **严格合规与瘦身**：FFmpeg 采用 LGPL 2.1+ 极简白名单裁剪，包体积增量仅 **~4.5MB**，零 GPL 法律风险。
- 🧩 **接口完全解耦 (Facade)**：采用门面模式，上层业务 API 可根据需求随意调整，与底层音视频管线互不影响。

---

## 🏗 整体架构

```
[业务接入层 (App)] ───► MediaPlayerController (统一门面) ───► MediaPlayerView (承载视图)
                                  │
[业务增强套件]      ├── PlayerPoolManager (短视频实例池)
                    ├── LocalPreloadProxy (边下边播预加载)
                    └── QoSAPMTracker (全链路质量监控)
                                  │
[引擎核心层]        ├── KSMEPlayer (FFmpeg Demux + VideoToolbox 硬解 + Metal 渲染)
                    └── KSAVPlayer (原生 AVFoundation 节能引擎)
                                  │
[底层加速]          └── FFmpeg.xcframework (LGPL) + Metal Shaders + AudioUnit
```

---

## 📦 集成方式

### 1. Swift Package Manager (SPM)
在 Xcode 中选择 `File` -> `Add Packages...`，输入仓库地址：
```
https://github.com/your-org/MediaPlayerKit.git
```

### 2. CocoaPods
在 `Podfile` 中添加：
```ruby
pod 'MediaPlayerKit', '~> 1.0.0'
```

---

## 🚀 快速上手

### 1. 基础点播与事件监听 (Swift)

```swift
import UIKit
import MediaPlayerKit

class VideoViewController: UIViewController, MediaPlayerDelegate {
    private let player = MediaPlayerController()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 1. 挂载渲染视图
        player.playerView.frame = view.bounds
        player.playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(player.playerView)
        
        // 2. 设置代理与播放源
        player.delegate = self
        if let videoURL = URL(string: "https://example.com/stream.m3u8") {
            player.setMediaSource(url: videoURL)
            player.play()
        }
    }
    
    // MARK: - MediaPlayerDelegate
    func player(_ player: MediaPlayerController, stateDidChange state: PlayerState) {
        print("播放器状态变更: \(state)")
    }
    
    func playerDidRenderFirstFrame(_ player: MediaPlayerController) {
        print("首帧渲染成功，起播耗时: \(player.currentQoSReport()?.firstFrameDuration ?? 0) ms")
    }
    
    func player(_ player: MediaPlayerController, currentTime: TimeInterval, totalDuration: TimeInterval) {
        // 更新 UI 进度条
    }
    
    func player(_ player: MediaPlayerController, didOccurError error: NSError) {
        print("播放错误: \(error.localizedDescription)")
    }
}
```

### 2. 短视频 Feed 流实例池与预加载 (TikTok / 抖音模式)

```swift
// UITableViewCell 渲染与复用
func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
    let videoItem = videoList[indexPath.row]
    
    // 1. 从池中取出预热的播放器实例
    let player = PlayerPoolManager.shared.dequeuePlayer()
    player.playerView.frame = cell.contentView.bounds
    cell.contentView.addSubview(player.playerView)
    
    // 2. 播放当前视频
    player.setMediaSource(url: videoItem.videoURL)
    player.play()
    
    // 3. 静默预加载下一个视频的前 1MB
    if indexPath.row + 1 < videoList.count {
        let nextURL = videoList[indexPath.row + 1].videoURL
        LocalPreloadProxy.shared.preload(url: nextURL, preloadBytes: 1024 * 1024)
    }
}

func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
    // 离开屏幕时归还播放器实例至池中
    if let player = currentCellPlayer {
        PlayerPoolManager.shared.recyclePlayer(player)
    }
}
```

---

## 🛠 脚本与构建

编译裁剪版 FFmpeg XCFramework：
```bash
cd Scripts
./build_ffmpeg_ios.sh
```

---

## 📄 开源许可证

本项目核心代码遵循 **MIT 许可证**，底层 FFmpeg 动态库遵循 **LGPL 2.1+ 许可证**。
