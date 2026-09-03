import SwiftUI

public struct ContentView: View {
    public init() {}

    public var body: some View {
        TabView {
            NavigationView {
                ShortVideoFeedView()
                    .navigationTitle("短视频流")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("短视频流", systemImage: "play.square.stack.fill")
            }
            
            NavigationView {
                UniversalPlayerView()
                    .navigationTitle("全能播放器")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("播放器", systemImage: "play.tv.fill")
            }
            
            NavigationView {
                QoSDashboardView()
                    .navigationTitle("QoS 大盘")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("QoS 大盘", systemImage: "chart.bar.xaxis")
            }
            
            NavigationView {
                SettingsView()
                    .navigationTitle("节点配置")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("配置", systemImage: "gearshape.fill")
            }
        }
        .accentColor(.blue)
    }
}
