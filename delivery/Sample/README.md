# 纯二进制消费样例

打包脚本自动放入 H5URLPlayerView.swift（从 Demo 当前实现提取，不含节点选流页）及 url-player.html。运行 xcodegen generate，再编译 BinarySDKSample。此工程只链接 SDK 二进制，不添加 MediaPlayerKit 源码。

project.yml 初始只声明主动态 framework。交付方必须根据 dependency-audit.json、otool 输出和真实消费结果，补齐第三方二进制及独立资源，然后通过此工程的编译和真机播放。若报缺失模块，不可通过加入 SDK 源码掩盖二进制交付问题。

默认关闭签名便于编译验证；真机测试需要选择业务自己的 Team、Bundle ID 并启用签名。此样例不预置鉴权、节点服务或可长期有效的测试地址；在 H5 输入可访问的 HTTPS 播放地址。
