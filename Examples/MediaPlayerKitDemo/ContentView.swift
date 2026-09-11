import SwiftUI
import MediaPlayerKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum AppTab: Int, CaseIterable {
    case feed = 0
    case player = 1
    case hybrid = 2
    case qos = 3
    case settings = 4
    
    public var title: String {
        switch self {
        case .feed: return "短视频流"
        case .player: return "原生播放器"
        case .hybrid: return "H5混合"
        case .qos: return "QoS 大盘"
        case .settings: return "节点配置"
        }
    }
    
    public var iconName: String {
        switch self {
        case .feed: return "play.square.stack.fill"
        case .player: return "play.tv.fill"
        case .hybrid: return "globe.americas.fill"
        case .qos: return "chart.bar.xaxis"
        case .settings: return "gearshape.fill"
        }
    }
}

public struct ContentView: View {
    @ObservedObject private var apiService = StreamAPIService.shared
    @State private var selectedTab: Int = 2 // 默认进入 H5 混合播放器体验满屏与底部导航

    @State private var showSDKLogs = false

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            ShortVideoFeedView()
                .tabItem {
                    Image(systemName: AppTab.feed.iconName)
                    Text(AppTab.feed.title)
                }
                .tag(AppTab.feed.rawValue)

            UniversalPlayerView()
                .tabItem {
                    Image(systemName: AppTab.player.iconName)
                    Text(AppTab.player.title)
                }
                .tag(AppTab.player.rawValue)

            H5DemoContainerView()
                .tabItem {
                    Image(systemName: AppTab.hybrid.iconName)
                    Text(AppTab.hybrid.title)
                }
                .tag(AppTab.hybrid.rawValue)

            NavigationView {
                QoSDashboardView()
            }
            .tabItem {
                Image(systemName: AppTab.qos.iconName)
                Text(AppTab.qos.title)
            }
            .tag(AppTab.qos.rawValue)

            NavigationView {
                SettingsView()
            }
            .tabItem {
                Image(systemName: AppTab.settings.iconName)
                Text(AppTab.settings.title)
            }
            .tag(AppTab.settings.rawValue)
        }
        .accentColor(.blue)
        .overlay(
            Button { showSDKLogs = true } label: {
                Label("SDK 日志", systemImage: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            #if os(iOS)
                            .fill(Color(.systemBackground).opacity(0.92))
                            #elseif os(macOS)
                            .fill(Color(NSColor.windowBackgroundColor).opacity(0.92))
                            #else
                            .fill(Color.primary.opacity(0.1))
                            #endif
                            .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
                    )
            }
            .padding(.trailing, 12)
            .padding(.top, 50),
            alignment: .topTrailing
        )
        .sheet(isPresented: $showSDKLogs) { SDKLogConsoleView() }
    }
}


/// Demo-only output. Never writes back to Logger (which would recurse).
final class DemoSDKLogStore: ObservableObject, Appender {
    static let shared = DemoSDKLogStore()
    struct Entry: Identifiable {
        let id = UUID()
        let time: String
        let level: String
        let group: String
        let kind: String
        let message: String
    }
    @Published private(set) var entries: [Entry] = []
    private let lock = NSLock()
    private var pending: [Entry] = []
    private var scheduled = false
    private let limit = 1000
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    func append(level: LogLevel, tag: String, message: String, messageType: MessageType) {
        lock.lock()
        let kind = messageType == .attachedLog ? "附加状态" : "普通日志"
        pending.append(Entry(time: formatter.string(from: Date()), level: level.label,
                             group: tag, kind: kind, message: String(message.prefix(8192))))
        if pending.count > limit { pending.removeFirst(pending.count - limit) }
        let shouldSchedule = !scheduled
        scheduled = true
        lock.unlock()
        if shouldSchedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.drain() }
        }
    }
    private func drain() {
        lock.lock()
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        scheduled = false
        lock.unlock()
        entries = Array((entries + batch).suffix(limit))
    }
    /// Called by the main-thread UI; discard pending entries as well.
    func clear() {
        lock.lock(); pending.removeAll(); lock.unlock()
        entries.removeAll()
    }
}

private struct SDKLogConsoleView: View {
    @ObservedObject private var store = DemoSDKLogStore.shared
    @Environment(\.presentationMode) private var presentationMode
    @State private var query = ""
    @State private var includeAttached = true
    @State private var copiedHint = false

    private var visibleEntries: [DemoSDKLogStore.Entry] {
        store.entries.filter {
            (includeAttached || $0.kind != "附加状态") &&
            (query.isEmpty || "\($0.group) \($0.level) \($0.message)".localizedCaseInsensitiveContains(query))
        }
    }

    private func levelColor(for level: String) -> Color {
        switch level.lowercased() {
        case "error", "fatal":
            return .red
        case "warn", "warning":
            return .orange
        case "info":
            return .blue
        case "debug":
            return .secondary
        default:
            return .primary
        }
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 8) {
                Text("SDK 原始日志 · 最近 1000 条 · 仅本次运行保存")
                    .font(.caption).foregroundColor(.secondary)
                TextField("筛选级别、分组或正文", text: $query)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Toggle("显示附加状态 attachedLogs", isOn: $includeAttached)
                    .font(.caption)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(visibleEntries.reversed()) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    Text(entry.time)
                                        .foregroundColor(.secondary)
                                    Text("[\(entry.level)]")
                                        .foregroundColor(levelColor(for: entry.level))
                                        .fontWeight(.semibold)
                                    Text("[\(entry.kind)]")
                                        .foregroundColor(entry.kind == "附加状态" ? .purple : .secondary)
                                    Text(entry.group)
                                        .foregroundColor(.secondary)
                                }
                                Text(entry.message)
                                    .foregroundColor(.primary)
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                        }
                    }
                }
                Text("最新记录在上方；广播事件仍在原页面查看。")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding()
            .navigationTitle("SDK 日志")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("清空") { store.clear() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    trailingToolbarButtons
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("清空") { store.clear() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    trailingToolbarButtons
                }
                #endif
            }
        }
    }

    private var trailingToolbarButtons: some View {
        HStack(spacing: 12) {
            Button(copiedHint ? "已复制" : "复制全部") {
                let text = visibleEntries.reversed().map {
                    "\($0.time) [\($0.level)] [\($0.kind)] \($0.group): \($0.message)"
                }.joined(separator: "\n")
                #if canImport(UIKit)
                UIPasteboard.general.string = text
                #elseif canImport(AppKit)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                #endif
                copiedHint = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copiedHint = false
                }
            }
            Button("关闭") { presentationMode.wrappedValue.dismiss() }
        }
    }
}
