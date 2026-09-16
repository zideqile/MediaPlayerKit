import SwiftUI
import WebKit
import MediaPlayerKit
#if canImport(UIKit)
import UIKit
#endif

/// App-specific URL submission; all standard controls/events use the SDK bridge.
private final class H5URLMessageHandler: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let bridge: PlayerBridge
    private var closed = false
    private var currentNavigation: WKNavigation?
    init(player: IH5Player) { bridge = PlayerBridge(player: player) }
    func close() { closed = true; bridge.detach() }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        currentNavigation = navigation
        bridge.invalidatePage()
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard navigation === currentNavigation else { return }
        bridge.commitPage()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard navigation === currentNavigation else { return }
        // Navigation failed before replacing the document; explicitly reconnect the retained page.
        bridge.commitPage()
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !closed else { return }
        bridge.handleMessage(message) { [weak self] method, json in
            guard method == "loadURL" else { return nil }
            return self?.loadURL(json) ?? ["ok": false, "error": "bridge_closed"]
        }
    }
    private func loadURL(_ json: String) -> [String: Any] {
        let invalid: [String: Any] = ["ok": false, "error": "请输入有效的 HTTP、HTTPS 或 RTMP 播放地址"]
        guard let data = json.data(using: .utf8),
              let params = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let input = params["url"] as? String else { return invalid }
        let address = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              ["http", "https", "rtmp"].contains(scheme), let host = url.host, !host.isEmpty,
              let type = params["type"] as? String, ["hls", "flv", "rtmp"].contains(type),
              (scheme == "rtmp") == (type == "rtmp") else { return invalid }
        guard let player = bridge.player else { return ["ok": false, "error": "player_unavailable"] }
        let isLive = params["isLive"] as? Bool ?? true
        let source = PlayerSource(url: address, type: type, tag: "H5 输入", isLive: isLive)
        let config = StreamAPIService.playbackConfig(for: player,
            topicId: params["topicId"] as? String ?? "topic_h5_url",
            streamId: params["streamId"] as? String ?? "")
        config.isLive = isLive
        player.setConfig(config)
        player.setSources([source])
        player.play()
        return ["ok": true, "result": ["url": address, "muted": config.muted]]
    }

}

private final class H5URLPlayerModel: ObservableObject {
    let playerView = MediaPlayerView()
    @Published var webView: WKWebView?
    @Published var error: String?
    private var player: IH5Player?
    private var handler: H5URLMessageHandler?

    func setup() {
        guard player == nil else { return }
        error = nil
        do {
            #if SWIFT_PACKAGE
            let bundles = [Bundle.module, Bundle.main]
            #else
            let bundles = [Bundle.main]
            #endif
            let url = bundles.compactMap { bundle in
                bundle.url(forResource: "url-player", withExtension: "html", subdirectory: "Resources/URLHybridPlayer")
                    ?? bundle.url(forResource: "url-player", withExtension: "html", subdirectory: "URLHybridPlayer")
                    ?? bundle.url(forResource: "url-player", withExtension: "html")
            }.first
            guard let url = url else {
                throw NSError(domain: "H5URLDemo", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到 url-player.html"])
            }
            let content = WKUserContentController()
            try PlayerBridge.installJavaScript(in: content)
            let player = export.CreateVZPlayer(playerView)
            let handler = H5URLMessageHandler(player: player)
            content.add(handler, name: "vzPlayerBridge")
            let configuration = WKWebViewConfiguration()
            configuration.userContentController = content
            let webView = WKWebView(frame: .zero, configuration: configuration)
            handler.bridge.webView = webView
            webView.navigationDelegate = handler
            self.player = player
            self.handler = handler
            self.webView = webView
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } catch {
            self.error = error.localizedDescription
        }
    }

    func teardown() {
        handler?.bridge.invalidatePage()
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "vzPlayerBridge")
        handler?.close()
        player?.destroy()
        player = nil
        handler = nil
        webView = nil
    }
}

struct H5URLPlayerView: View {
    @StateObject private var model = H5URLPlayerModel()
    var body: some View {
        VStack(spacing: 0) {
            DemoPlayerSurface(playerView: model.playerView)
                .frame(height: 220)
                .background(Color.black)
            if let webView = model.webView {
                HybridWKWebViewRepresentable(webView: webView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.error {
                Text(error).foregroundColor(.red).padding()
                Button("重新加载") { model.setup() }
            } else {
                ProgressView().padding()
            }
        }
        .onAppear { model.setup() }
        .onDisappear {
            DemoPlayerSurface.exitFullScreen(for: model.playerView)
            model.teardown()
        }
    }
}

/// Keep both H5 samples inside the existing tab to avoid iPhone's sixth-tab overflow.
struct H5DemoContainerView: View {
    @State private var page = 0
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - 顶部安全区避让与模式切换栏
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "globe.americas.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 13, weight: .semibold))
                    Text("H5 混合播放")
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Text(page == 0 ? "预置流节点调度" : "自定义 URL 输入")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                
                Picker("H5 示例", selection: $page) {
                    Text("节点选流").tag(0)
                    Text("输入地址").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
            #if canImport(UIKit)
            .background(Color(UIColor.secondarySystemBackground).edgesIgnoringSafeArea(.top))
            #else
            .background(Color.gray.opacity(0.1))
            #endif
            .overlay(Divider(), alignment: .bottom)

            if page == 0 { WebViewHybridPlayerView() }
            else { H5URLPlayerView() }
        }
    }
}
