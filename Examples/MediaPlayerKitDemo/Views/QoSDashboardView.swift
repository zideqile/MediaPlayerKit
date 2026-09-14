import SwiftUI
import MediaPlayerKit

/// Keep the latest real snapshot even after leaving a playback tab destroys its player.
final class DemoPlaybackStatisticsStore: ObservableObject {
    static let shared = DemoPlaybackStatisticsStore()
    @Published private(set) var latest: [String: Any] = [:]
    private var observer: NSObjectProtocol?
    private init() {
        observer = NotificationCenter.default.addObserver(forName: PlayerStatisticsEvents.didUpdate,
                                                         object: nil, queue: .main) { [weak self] event in
            self?.latest = event.userInfo as? [String: Any] ?? [:]
        }
    }
    deinit { if let observer = observer { NotificationCenter.default.removeObserver(observer) } }
}

public struct QoSDashboardView: View {
    @ObservedObject private var store = DemoPlaybackStatisticsStore.shared
    public init() {}
    private func number(_ value: Any?, unit: String = "", scale: Double = 1) -> String {
        guard let n = value as? NSNumber, n.doubleValue.isFinite else { return "未采集" }
        return String(format: "%.2f", n.doubleValue * scale) + unit
    }
    public var body: some View {
        let data = store.latest
        let session = data["session"] as? [String: Any] ?? [:]
        let metrics = data["metrics"] as? [String: Any] ?? [:]
        return List {
            if data.isEmpty {
                Text("暂无统计。播放视频后可查看实际采集结果。")
            } else {
                Section(header: Text("最近播放会话")) {
                    Text("内核：\(data["engine"] as? String ?? "未创建")")
                    Text("来源：\(data["sourceUrl"] as? String ?? "")").font(.caption)
                    Text("更新原因：\(data["reason"] as? String ?? "")").font(.caption)
                    Text("会话：\(data["sessionId"] as? String ?? "")").font(.caption2)
                }
                Section(header: Text("播放质量 · 会话累计")) {
                    row("有效播放时长", number(session["playDurationMs"], unit: " s", scale: 0.001))
                    row("卡顿总时长", number(session["stalledTotalDuration"], unit: " s", scale: 0.001))
                    row("卡顿次数", number(session["stalledCount"]))
                    row("卡顿占比", number(session["stallRatio"], unit: "%", scale: 100))
                    row("当前尝试首帧耗时", number(data["firstFrameDurationMs"], unit: " ms"))
                    row("当前内核创建耗时", number(data["creationDurationMs"], unit: " ms"))
                }
                Section(header: Text("切源与恢复 · 会话累计")) {
                    row("播放尝试", number(data["attemptCount"]))
                    row("切换播放源", number(data["sourceSwitchCount"]))
                    row("同源切换内核", number(data["engineSwitchCount"]))
                    row("尝试失败", number(data["errorCount"]))
                    row("恢复成功", number(data["recoverySuccessCount"]))
                    row("恢复失败", number(data["recoveryFailureCount"]))
                    row("恢复取消", number(data["recoveryCancelledCount"]))
                    row("最近恢复耗时", number(data["recoveryDurationMs"], unit: " ms"))
                }
                Section(header: Text("最近内核采样 · 非逐请求统计")) {
                    row("显示帧率", number(metrics["fps"], unit: " fps"))
                    row("视频标称帧率", number(metrics["frame_rate"], unit: " fps"))
                    row("观测码率", number(metrics["bitrate"], unit: " bps"))
                    row("网络下载速度", number(metrics["net_speed"], unit: " B/s"))
                    row("网络传输字节", number(metrics["net_bytes"], unit: " B"))
                    row("媒体请求数", number(metrics["media_requests"]))
                    Text("DNS、TCP、首包耗时和分片请求明细暂未采集，不以 0 代替。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("QoS 质量大盘")
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title).font(.subheadline); Spacer(); Text(value).font(.system(.caption, design: .monospaced)) }
    }
}
