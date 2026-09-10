# Demo 源码 / 二进制依赖切换

默认配置在 Config/DemoBuild.json：mode=binary，sdkDirectory=build/binary-delivery/SDK，platform=device。project.yml 是基础源码工程模板，不再直接用于 CI Demo 产物。

工具依赖：macOS、Xcode、XcodeGen、Python 3 + PyYAML（CI 固定安装 6.0.2）。

## 二进制模式（默认）

```sh
bash scripts/build_binary_delivery.sh 218
python3 scripts/generate_demo_project.py
xcodegen generate --spec project.generated.yml
```

打开 MediaPlayerKitDemoBinary.xcodeproj。它只有 Demo Target，没有 SDK 源码 Target，也没有 KSPlayer/FFmpeg 源码包。SDK 主库内部使用的 KSPlayer 回调由私有代理承接，implementation-only import 避免消费端需要源码模块。

SDK/ 下的动态 XCFramework 自动链接并嵌入，SDK/Resources/device 下的资源包进入 App。构建模拟器时用 `--platform simulator` 重新生成；生成配置只选择对应平台资源。SDK 内静态链接的库无需重复加入 App；发现无法解析的动态依赖或资源缺失时打包失败，不能默默回退到源码。

使用外部交付目录：

```sh
python3 scripts/generate_demo_project.py --mode binary --sdk-dir /path/to/delivery/SDK --platform device
xcodegen generate --spec project.generated.yml
```

外部目录应遵循同样结构，并通过交付检查。生成器不会替业务猜测任意第三方包的静态/动态类型。--sdk-dir 仅用于已经组装好的二进制交付目录。

## 源码调试模式

```sh
python3 scripts/generate_demo_project.py --mode source
xcodegen generate --spec project.generated.yml
```

打开 MediaPlayerKitDemo.xcodeproj，可修改 SDK 源码调试。也可把 Config/DemoBuild.json 的 mode 改为 source。原 project.yml 保留，可直接生成原源码工程；这不是二进制验收模式。

## CI 顺序

1. 校验并生成一次构建版本元数据。
2. 生成只含 SDK Target 的 MediaPlayerKitSDK.xcodeproj。
3. 分别归档 iOS 真机/模拟器 SDK，组装 XCFramework；收集动态依赖和平台资源。
4. 检查 Swift interface 不再要求 KSPlayer/FFmpegKit/DisplayCriteria 模块。
5. 用生成目录创建独立 Demo 工程，使用独立 DerivedData 构建 Demo。
6. 原 CI 继续完成真机 App 的签名和 IPA 分发；上传 SDK、版本清单与依赖报告供追踪。

普通 CI 可用仓库变量 MPK_DEMO_MODE=source 临时覆盖默认值；显式 source 模式产物不能用来证明二进制可交付。Release 与 Binary Delivery 工作流强制 binary，避免误用调试模式发布。

Release 当前改为 iOS 二进制 SDK + 二进制依赖的模拟器 Demo；停止把模拟器 App 包装成真机 IPA，也不再把源码 SPM 的 macOS Demo 混入这次 iOS 二进制交付验证。macOS 二进制交付需要单独构建对应平台切片。

原 MediaPlayerKitDemo 的功能页面不变。源码单元测试仍可另行运行，但不是二进制 Demo 验收的替代品。

## 验证边界

Linux 已验证生成配置、依赖隔离、资源选择、脚本与工作流语法。Xcode 编译、模块稳定性、动态库加载和资源运行时加载必须以 macOS CI 和真机结果为准。CI 编译通过后仍需播放与生命周期验收，不能据此自动宣称整个 SDK 已交付合格。
