import SwiftUI
import MediaPlayerKit

#if canImport(UIKit)
import UIKit

/// Keep SwiftUI's inline slot mounted while moving only the complete SDK container.
/// No modal presentation, player recreation, forced device rotation or playback commands.
struct DemoPlayerSurface: UIViewRepresentable {
    let playerView: MediaPlayerView
    var onVideoTap: (() -> Void)? = nil

    func makeUIView(context: Context) -> DemoPlayerHost {
        DemoPlayerHost(playerView: playerView, onVideoTap: onVideoTap)
    }
    func updateUIView(_ uiView: DemoPlayerHost, context: Context) {
        uiView.onVideoTap = onVideoTap
        uiView.refreshEngineName()
    }
    static func dismantleUIView(_ uiView: DemoPlayerHost, coordinator: ()) {
        uiView.close()
    }
    static func exitFullScreen(for playerView: MediaPlayerView) {
        guard let host = DemoPlayerHost.fullscreenHost, host.playerView === playerView else { return }
        host.exitFullScreen()
    }
}

final class DemoPlayerHost: UIView, UIGestureRecognizerDelegate {
    fileprivate static weak var fullscreenHost: DemoPlayerHost?
    let playerView: MediaPlayerView
    var onVideoTap: (() -> Void)?
    private let stage = UIView()
    private let engineLabel = UILabel()
    private let fullscreenButton = UIButton(type: .system)
    private var fullscreenOverlay: UIView?
    private var timer: Timer?

    init(playerView: MediaPlayerView, onVideoTap: (() -> Void)?) {
        self.playerView = playerView
        self.onVideoTap = onVideoTap
        super.init(frame: .zero)
        backgroundColor = .black
        stage.backgroundColor = .black
        stage.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(stage)
        playerView.translatesAutoresizingMaskIntoConstraints = true
        playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        stage.addSubview(playerView)

        engineLabel.textColor = .white
        engineLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        engineLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        engineLabel.layer.cornerRadius = 5
        engineLabel.clipsToBounds = true
        engineLabel.numberOfLines = 2
        fullscreenButton.tintColor = .white
        fullscreenButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        fullscreenButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        fullscreenButton.layer.cornerRadius = 8
        fullscreenButton.addTarget(self, action: #selector(toggleFullScreen), for: .touchUpInside)
        for control in [engineLabel, fullscreenButton] as [UIView] {
            control.translatesAutoresizingMaskIntoConstraints = false
            stage.addSubview(control)
        }
        NSLayoutConstraint.activate([
            engineLabel.leadingAnchor.constraint(equalTo: stage.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            engineLabel.bottomAnchor.constraint(equalTo: stage.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            engineLabel.trailingAnchor.constraint(lessThanOrEqualTo: fullscreenButton.leadingAnchor, constant: -8),
            fullscreenButton.trailingAnchor.constraint(equalTo: stage.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            fullscreenButton.bottomAnchor.constraint(equalTo: stage.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            fullscreenButton.widthAnchor.constraint(equalToConstant: 96),
            fullscreenButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(videoTapped))
        tap.delegate = self
        stage.addGestureRecognizer(tap)
        refreshEngineName()
        updateFullscreenButton()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // While expanded the window is the sole sizing owner of stage.
        if stage.superview === self, stage.frame != bounds { stage.frame = bounds }
        if playerView.frame != stage.bounds { playerView.frame = stage.bounds }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        timer?.invalidate(); timer = nil
        guard window != nil else { exitFullScreen(); return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshEngineName() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func refreshEngineName() {
        let text = " 内核：\(playerView.currentEngineName ?? "未创建") "
        if engineLabel.text != text { engineLabel.text = text }
    }
    @objc private func toggleFullScreen() {
        if fullscreenOverlay != nil { exitFullScreen(); return }
        guard let window = window else { return }
        Self.fullscreenHost?.exitFullScreen()
        let overlay = UIView(frame: window.bounds)
        overlay.accessibilityViewIsModal = true
        overlay.backgroundColor = .black
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        fullscreenOverlay = overlay
        Self.fullscreenHost = self
        window.addSubview(overlay)
        overlay.addSubview(stage)
        stage.frame = overlay.bounds
        playerView.frame = stage.bounds
        updateFullscreenButton()
        refreshEngineName()
        UIAccessibility.post(notification: .layoutChanged, argument: fullscreenButton)
    }
    func exitFullScreen() {
        guard let overlay = fullscreenOverlay else { return }
        fullscreenOverlay = nil
        addSubview(stage)
        stage.frame = bounds
        playerView.frame = stage.bounds
        overlay.removeFromSuperview()
        if Self.fullscreenHost === self { Self.fullscreenHost = nil }
        updateFullscreenButton()
    }
    private func updateFullscreenButton() {
        let expanded = fullscreenOverlay != nil
        fullscreenButton.setTitle(expanded ? "退出全屏" : "全屏", for: .normal)
        fullscreenButton.setImage(UIImage(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"), for: .normal)
        fullscreenButton.accessibilityLabel = expanded ? "退出全屏播放" : "全屏播放"
    }
    @objc private func videoTapped() { onVideoTap?() }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard onVideoTap != nil else { return false }
        var view = touch.view
        while let current = view, current !== stage {
            if current is UIControl { return false }
            view = current.superview
        }
        return true
    }
    func close() {
        timer?.invalidate(); timer = nil
        exitFullScreen()
    }
    deinit {
        timer?.invalidate()
        fullscreenOverlay?.removeFromSuperview()
    }
}
#else
struct DemoPlayerSurface: View {
    let playerView: MediaPlayerView
    var onVideoTap: (() -> Void)? = nil
    var body: some View { PlayerViewRepresentable(playerView: playerView) }
    static func exitFullScreen(for playerView: MediaPlayerView) {}
}
#endif
