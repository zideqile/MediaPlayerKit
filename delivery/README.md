# MediaPlayerKit iOS 二进制交付准备包

当前状态：文档和打包流程已准备；本目录不含已经编译、验收的 XCFramework。正式交付必须在 macOS/Xcode 完成构建、依赖闭包检查和真机验收。

- 业务接入：Docs/Integration.md
- H5 协议：Docs/H5-API.md
- 验收与交付清单：Docs/Acceptance.md
- 最小消费工程：Sample（只引用交付的二进制，不引用 SDK 源码）
- 构建命令：在仓库根目录运行 `bash scripts/build_binary_delivery.sh 218`，218 替换为发行构建号。

构建产物输出到 build/binary-delivery/，标记为 CANDIDATE。不能直接把候选包作为正式发布包发送。

正式包结构：SDK/MediaPlayerKit.xcframework、必要的第三方二进制与资源、Docs/、Sample/、Licenses/、version-manifest.json、Package.resolved、SHA256SUMS。第三方依赖是否合入主库必须以实际产物检查为准，不允许用空目录或仅主 framework 冒充完整 SDK。
