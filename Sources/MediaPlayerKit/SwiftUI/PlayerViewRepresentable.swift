import SwiftUI

#if canImport(UIKit)
import UIKit

/// SwiftUI 跨平台播放器视图包装器 (iOS / tvOS / visionOS)
public struct PlayerViewRepresentable: UIViewRepresentable {
    public let player: MediaPlayerController

    public init(player: MediaPlayerController) {
        self.player = player
    }

    public func makeUIView(context: Context) -> MediaPlayerView {
        return player.playerView
    }

    public func updateUIView(_ uiView: MediaPlayerView, context: Context) {}
}

#elseif canImport(AppKit)
import AppKit

/// SwiftUI 跨平台播放器视图包装器 (macOS)
public struct PlayerViewRepresentable: NSViewRepresentable {
    public let player: MediaPlayerController

    public init(player: MediaPlayerController) {
        self.player = player
    }

    public func makeNSView(context: Context) -> MediaPlayerView {
        return player.playerView
    }

    public func updateNSView(_ nsView: MediaPlayerView, context: Context) {}
}
#endif
