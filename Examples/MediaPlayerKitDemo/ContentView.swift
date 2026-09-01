import SwiftUI

public struct ContentView: View {
    public init() {}

    public var body: some View {
        TabView {
            NavigationView {
                UniversalPlayerView()
                    .navigationTitle("全能播放器")
            }
            .tabItem {
                Label("播放器", systemImage: "play.tv.fill")
            }
            
            NavigationView {
                ShortVideoFeedView()
                    .navigationTitle("短视频秒开")
            }
            .tabItem {
                Label("短视频流", systemImage: "iphone.badge.play")
            }
            
            NavigationView {
                QoSDashboardView()
            }
            .tabItem {
                Label("QoS 大盘", systemImage: "chart.bar.xaxis")
            }
        }
    }
}
