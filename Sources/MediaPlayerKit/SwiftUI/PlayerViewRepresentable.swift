import SwiftUI

#if canImport(UIKit)
import UIKit

/// SwiftUI 跨平台播放器视图包装器 (iOS / tvOS / visionOS)
public struct PlayerViewRepresentable: UIViewRepresentable {
    public let playerView: MediaPlayerView

    public init(playerView: MediaPlayerView) {
        self.playerView = playerView
    }

    public init(player: MediaPlayerController) {
        self.playerView = player.playerView
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

/// SwiftUI 跨平台播放器视图包装器 (macOS)
public struct PlayerViewRepresentable: NSViewRepresentable {
    public let playerView: MediaPlayerView

    public init(playerView: MediaPlayerView) {
        self.playerView = playerView
    }

    public init(player: MediaPlayerController) {
        self.playerView = player.playerView
    }

    public func makeNSView(context: Context) -> MediaPlayerView {
        return playerView
    }

    public func updateNSView(_ nsView: MediaPlayerView, context: Context) {
        nsView.needsLayout = true
    }
}
#endif
