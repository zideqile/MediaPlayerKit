import SwiftUI
import WebKit
import MediaPlayerKit

@main
struct BinarySDKSampleApp: App {
    init() {
        let options = InitConfig()
        options.appenders = ["ConsoleAppender"]
        export.Init(options, "{\"env\":\"test\"}")
    }
    var body: some Scene { WindowGroup { H5URLPlayerView() } }
}
struct PlayerViewRepresentable: UIViewRepresentable {
    let playerView: MediaPlayerView
    func makeUIView(context: Context) -> MediaPlayerView { playerView }
    func updateUIView(_ view: MediaPlayerView, context: Context) {}
}
struct HybridWKWebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
