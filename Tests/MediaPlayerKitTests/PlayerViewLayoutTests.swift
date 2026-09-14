import XCTest
@testable import MediaPlayerKit
#if canImport(UIKit)
import UIKit

@MainActor
final class PlayerViewLayoutTests: XCTestCase {
    func testInlineLayoutDoesNotResizeReparentedRenderView() {
        let inline = MediaPlayerView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let render = UIView()
        inline.attachRenderView(render)
        let fullscreen = UIView(frame: CGRect(x: 0, y: 0, width: 844, height: 390))
        fullscreen.addSubview(render)
        render.frame = fullscreen.bounds
        inline.layoutSubviews()
        XCTAssertEqual(render.frame, fullscreen.bounds)
        XCTAssertTrue(render.superview === fullscreen)
    }

    func testMovingWholeContainerPreservesRenderIdentityAndRestoresSize() {
        let inline = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let fullscreen = UIView(frame: CGRect(x: 0, y: 0, width: 844, height: 390))
        let player = MediaPlayerView(frame: inline.bounds)
        let render = UIView()
        player.attachRenderView(render)
        inline.addSubview(player)
        for _ in 0..<5 {
            fullscreen.addSubview(player)
            player.frame = fullscreen.bounds
            player.layoutSubviews()
            XCTAssertTrue(render.superview === player)
            XCTAssertEqual(render.frame.size, fullscreen.bounds.size)
            inline.addSubview(player)
            player.frame = inline.bounds
            player.layoutSubviews()
            XCTAssertTrue(render.superview === player)
            XCTAssertEqual(render.frame.size, inline.bounds.size)
        }
    }

    func testEngineLabelFollowsNestedReplacementAndDetach() {
        let outer = MediaPlayerView()
        let first = MediaPlayerView()
        first.engineDisplayName = "AVPlayer"
        first.attachRenderView(UIView())
        outer.attachRenderView(first)
        XCTAssertEqual(outer.currentEngineName, "AVPlayer")
        let fallback = MediaPlayerView()
        fallback.engineDisplayName = "KSPlayer / FFmpeg"
        fallback.attachRenderView(UIView())
        outer.attachRenderView(fallback)
        XCTAssertEqual(outer.currentEngineName, "KSPlayer / FFmpeg")
        outer.detachRenderView()
        XCTAssertNil(outer.currentEngineName)
    }
}
#endif
