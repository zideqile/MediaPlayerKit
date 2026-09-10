# SDK 与 Demo 版本管理

SDK_VERSION、DEMO_VERSION 是两个独立的发布版本来源，当前均保留为 1.0.0，不代表本次已发布。修复兼容问题增加 patch；向后兼容功能增加 minor；不兼容 API、JS 返回值或事件变化增加 major。脚本不猜测改动性质、不自动升级版本、不提交、不打 Tag。

## 日常修改

1. 按实际发布范围修改 SDK_VERSION 或 DEMO_VERSION。
2. 运行 `python3 scripts/generate_versions.py`。
3. 运行 `python3 scripts/generate_versions.py --check`。
4. 将版本文件及生成的 Swift、xcconfig 文件一起提交。

生成文件包括 SDKVersion.swift、DemoVersion.swift、Config/Versions.xcconfig。podspec 直接读取 SDK_VERSION。XcodeGen 两个 target 分别采用 SDK/Demo marketing version，Info.plist 通过 Xcode build setting 展开；不要直接用未展开的源码 plist 充当最终 App plist。

未构建的源码默认标记为 `1.0.0+development`，不伪造日期和 commit。XcodeGen 生成的工程在本地构建 SDK 前自动运行 `--build`，读取当前 Git HEAD 和当前北京时间（UTC+8）；CI 使用其预先生成的统一元数据。直接通过源码 SPM 或 CocoaPods 构建时，构建前运行 `python3 scripts/generate_versions.py --build`；无脚本执行的源码消费保留 development 标记，可通过 releaseVersion 获取纯发布版本。

构建完成后生成文件会有变化，提交前执行无参数生成恢复开发模板。commit 指构建时 HEAD，不能单靠它证明本地没有未提交修改；正式发行使用干净的 CI checkout。

## CI 构建与发布

现有 CI 和 Release 工作流均先校验生成文件，再按 github.run_number、github.sha 生成构建元数据，不提交构建产物回仓库。重跑同一个 run 保持构建号不变；如果需要作为一次新的安装发布，请触发新 run。

注意：run_number 在单个工作流内递增，并非跨工作流全局计数。当前实际设备 IPA 使用 CI 工作流的计数；Release 工作流的计数用于该发布产物。不要将两个工作流的计数混入同一个应用分发序列；后续新增分发流水线时应统一至一个发行计数来源。Artifact 名称附带构建号和 commit，version-manifest.json 同时记录 SDK/Demo 版本、构建号、commit 和 Tag。

SDK Release Tag 必须精确为 `v` 加 SDK_VERSION，例如 v1.0.0；不匹配会在编译前失败。带 Tag 的发布还要求非零构建号和有效 commit。不要移动已经发布的 Tag。Demo 可以单独升级版本，经 CI 工作流构建，无需为此升级 SDK。

示例（构建号由实际流水线提供，commit 使用实际 Git revision）：

```sh
python3 scripts/generate_versions.py \
  --build-number 218 \
  --commit abcdef1234567 \
  --release-tag v1.0.0 \
  --manifest build/version-manifest.json
```

CI 的 Xcode 工程使用生成的 xcconfig，macOS 打包 plist 从 manifest 写入相同版本。CI 签名、SDK 二进制及 App 的完整产物仍需 macOS 构建验证，本脚本不替代发布验收。

## 完整构建版本

SDK 与 Demo 都采用 `发布版本+北京时间构建时间(UTC+8).短commit.构建号`，例如：

`1.2.3+20260910183000(UTC+8).abcdef123456.218`

日期是生成构建元数据的北京时间（UTC+8），后缀 (UTC+8) 明确表示时区，精确到秒，不使用运行时日期或 commit 的提交日期。短 commit 最多 12 位，完整 commit 另存。CI 在编译之前生成一次，所以 SDK、Demo 和 manifest 使用一致的日期。可用 `--build-date "20260910183000(UTC+8)"` 显式指定，便于重现相同元数据。

- export.GetVersion() / SDKVersion.version：完整构建版本。
- SDKVersion.releaseVersion：纯三段发布版本。
- SDKVersion.buildDate / buildNumber / commit：分开的构建字段。
- DemoVersion 提供相同结构，使用独立 Demo 发布版本。
- 日志上传记录 version 直接使用 SDK 完整构建版本；删除固定值 "2" 和 GetLogCompatibilityVersion 接口。直接 Logger.initialize 默认也使用 SDKVersion.version，仍允许调用方显式覆盖。
- Demo 设置页显示完整构建版本。

SDK_VERSION、DEMO_VERSION、podspec、Tag 和 CFBundleShortVersionString 继续使用纯三段版本；CFBundleVersion 保留纯数字构建号。日期和 commit 放在完整版本标识中，不写入这些安装包版本字段。

JS 桥接随 SDK 版本交付，不单独维护另一套发行版本号。

## 校验

`python3 -m unittest discover -s Tests/Scripts -v` 验证独立版本、日期与 commit 拼接、非法日期、Tag 匹配和确定性生成。
