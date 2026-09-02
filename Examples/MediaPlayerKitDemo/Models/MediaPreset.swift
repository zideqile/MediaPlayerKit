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
            title: "HTTP-FLV 高清直播流 (KSPlayer/FFmpeg)",
            subtitle: "低延迟 FLV 解封装与硬件解码",
            url: URL(string: "https://cctvtxyh5ca.v.myalicdn.com/live/cctv13_2/index.flv")!,
            format: "HTTP-FLV",
            isLive: true
        ),
        MediaPreset(
            title: "RTMP 实时音视频流 (KSPlayer/FFmpeg)",
            subtitle: "标准 RTMP 传输协议拉流测试",
            url: URL(string: "rtmp://ns8.indexforce.com/home/mystream")!,
            format: "RTMP",
            isLive: true
        ),
        MediaPreset(
            title: "Tears of Steel (4K HDR 演示流)",
            subtitle: "高码率 HEVC / 宽色域 BT.2020",
            url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4")!,
            format: "MP4 (HDR)",
            isLive: false
        ),
        MediaPreset(
            title: "CCTV-13 高清新闻直播 (HLS 直播)",
            subtitle: "央视新闻标准 HLS 直播源",
            url: URL(string: "https://cctvtxyh5ca.v.myalicdn.com/live/cctv13_2/index.m3u8")!,
            format: "HLS Live",
            isLive: true
        )
    ]
}
