import SwiftUI

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
    }
}
