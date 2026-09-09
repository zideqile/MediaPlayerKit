import SwiftUI

#if canImport(UIKit)
import UIKit

/// 针对 VZPlayer (IH5Player / IPlayer) 的 SwiftUI 渲染视图封装
public struct VZPlayerViewRepresentable: UIViewRepresentable {
    public let playerView: MediaPlayerView

    public init(playerView: MediaPlayerView) {
        self.playerView = playerView
    }

    public func makeUIView(context: Context) -> MediaPlayerView {
        return playerView
    }

    public func updateUIView(_ uiView: MediaPlayerView, context: Context) {
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
    }
}

#elseif canImport(AppKit)
import AppKit

/// 针对 VZPlayer (IH5Player / IPlayer) 的 SwiftUI 渲染视图封装 (macOS)
public struct VZPlayerViewRepresentable: NSViewRepresentable {
    public let playerView: MediaPlayerView

    public init(playerView: MediaPlayerView) {
        self.playerView = playerView
    }

    public func makeNSView(context: Context) -> MediaPlayerView {
        return playerView
    }

    public func updateNSView(_ nsView: MediaPlayerView, context: Context) {
        nsView.needsLayout = true
    }
}
#endif
