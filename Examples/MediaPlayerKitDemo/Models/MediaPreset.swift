import Foundation

public struct MediaPreset: Identifiable, Hashable {
    public let id = UUID()
    public let title: String
    public let subtitle: String
    public let url: URL
    public let format: String
    public let isLive: Bool
    
    public static let samples: [MediaPreset] = [
        MediaPreset(
            title: "Big Buck Bunny (1080P MP4)",
            subtitle: "标准高清点播 / H.264 + AAC",
            url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!,
            format: "MP4",
            isLive: false
        ),
        MediaPreset(
            title: "Apple HLS Master Playlist (多码率自适应)",
            subtitle: "HLS / m3u8 多分辨率自适应流",
            url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8")!,
            format: "HLS",
            isLive: false
        ),
        MediaPreset(
            title: "Tears of Steel (4K HDR 演示流)",
            subtitle: "高码率 HEVC / 宽色域 BT.2020",
            url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4")!,
            format: "MP4 (HDR)",
            isLive: false
        ),
        MediaPreset(
            title: "CCTV-13 高清新闻直播 (FLV/HLS)",
            subtitle: "低延迟直播流测试",
            url: URL(string: "https://cctvtxyh5ca.v.myalicdn.com/live/cctv13_2/index.m3u8")!,
            format: "HLS Live",
            isLive: true
        )
    ]
}
