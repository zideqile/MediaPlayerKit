import SwiftUI

public enum AppTab: String, CaseIterable {
    case feed = "短视频流"
    case player = "播放器demo"
    case qos = "QoS 大盘"
    case settings = "节点配置"
    
    public var title: String {
        return self.rawValue
    }
    
    public var iconName: String {
        switch self {
        case .feed: return "play.square.stack.fill"
        case .player: return "play.tv.fill"
        case .qos: return "chart.bar.xaxis"
        case .settings: return "gearshape.fill"
        }
    }
}

public struct ContentView: View {
    @ObservedObject private var apiService = StreamAPIService.shared
    @State private var selectedTab: AppTab = .feed

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 1. 顶部统一定义的导航栏（同层线性排布）
            HStack {
                Text(selectedTab.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // 快捷节点指示状态
                if !apiService.nodeItems.isEmpty && (selectedTab == .feed || selectedTab == .player) {
                    HStack(spacing: 3) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 9))
                        Text(apiService.activeNodeItem?.remark.isEmpty == false ? apiService.activeNodeItem!.remark : apiService.activeNodeDomain)
                            .font(.system(size: 10, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.06))
            
            Divider()
            
            // MARK: - 2. 主界面内容区域（同层占满剩余空间，绝对不与导航栏遮挡）
            ZStack {
                switch selectedTab {
                case .feed:
                    ShortVideoFeedView()
                case .player:
                    UniversalPlayerView()
                case .qos:
                    QoSDashboardView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // MARK: - 3. 底部导航栏（同层线性排布在最下方，绝不遮挡主界面内容）
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button(action: {
                        selectedTab = tab
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 20))
                            Text(tab.title)
                                .font(.system(size: 10, weight: selectedTab == tab ? .bold : .regular))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundColor(selectedTab == tab ? .blue : .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .background(Color.secondary.opacity(0.06))
        }
    }
}
