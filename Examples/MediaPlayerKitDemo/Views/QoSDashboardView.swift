import SwiftUI
import MediaPlayerKit

public struct QoSDashboardView: View {
    public init() {}

    public var body: some View {
        List {
            Section(header: Text("核心起播度量指标 (SLO)")) {
                MetricRow(title: "平均首帧耗时 (P95)", value: "48.2 ms", status: "优秀 (<100ms)", color: .green)
                MetricRow(title: "DNS 预解析耗时", value: "12.4 ms", status: "正常", color: .blue)
                MetricRow(title: "TCP 建连耗时", value: "24.1 ms", status: "正常", color: .blue)
                MetricRow(title: "首包响应耗时 (TTFB)", value: "32.0 ms", status: "正常", color: .blue)
            }
            
            Section(header: Text("播放稳定性度量")) {
                MetricRow(title: "百秒卡顿次数", value: "0.02 次/100s", status: "极佳", color: .green)
                MetricRow(title: "百秒卡顿总时长", value: "0.15 s/100s", status: "极佳", color: .green)
                MetricRow(title: "硬解丢帧率", value: "0.01%", status: "极佳 (<0.1%)", color: .green)
                MetricRow(title: "崩溃率 (Crash Rate)", value: "0.00%", status: "零崩溃", color: .green)
            }
            
            Section(header: Text("硬件能耗与渲染")) {
                MetricRow(title: "解码器类型", value: "VideoToolbox (NV12)", status: "硬件加速", color: .green)
                MetricRow(title: "渲染管线", value: "MetalKit (Zero-Copy)", status: "GPU 显存直通", color: .green)
                MetricRow(title: "平均 CPU 占用率", value: "7.8% (1080P60)", status: "低能耗", color: .green)
            }
        }
        #if os(iOS)
        .listStyle(InsetGroupedListStyle())
        #endif
        .navigationTitle("QoS 质量大盘")
    }
}

struct MetricRow: View {
    let title: String
    let value: String
    let status: String
    let color: Color
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline)
                Text(status).font(.caption2).foregroundColor(color)
            }
            Spacer()
            Text(value).font(.system(size: 15, weight: .semibold, design: .monospaced))
        }
        .padding(.vertical, 2)
    }
}
