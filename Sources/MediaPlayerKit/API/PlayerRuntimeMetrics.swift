import Foundation

/// Optional measurements: nil means unavailable, never an implicit zero.
public struct PlayerRuntimeMetrics {
    public var displayFPS: Double?
    public var nominalFrameRate: Double?
    public var bytesRead: Int64?
    public var networkBytes: Int64?
    public var droppedVideoFrames: Int64?
    public var droppedVideoPackets: Int64?
    public var mediaRequests: Int64?
    public var observedBitrate: Double?
    public init() {}
}

/// Counter differences use monotonic elapsed time. Reset on source/engine changes and pause.
struct RuntimeMetricsSampler {
    private var previousTime: TimeInterval?
    private var previous: [String: Int64] = [:]
    mutating func sample(_ metrics: PlayerRuntimeMetrics, at time: TimeInterval) -> [String: Double] {
        guard time.isFinite else { return [:] }
        var result: [String: Double] = [:]
        for (key, value) in [("fps", metrics.displayFPS), ("frame_rate", metrics.nominalFrameRate),
                             ("ios_observed_bitrate_bps", metrics.observedBitrate)] {
            if let value = value, value.isFinite, value >= 0,
               key == "fps" || value > 0 { result[key] = value }
        }
        let counters: [(String, Int64?)] = [
            ("ios_bytes_read", metrics.bytesRead), ("ios_network_bytes", metrics.networkBytes),
            ("ios_dropped_video_frames", metrics.droppedVideoFrames),
            ("ios_dropped_video_packets", metrics.droppedVideoPackets),
            ("ios_media_requests", metrics.mediaRequests)
        ]
        let elapsed = previousTime.map { time - $0 }
        var next: [String: Int64] = [:]
        for (key, value) in counters {
            guard let value = value, value >= 0 else { continue }
            next[key] = value
            guard let elapsed = elapsed, elapsed > 0,
                  let old = previous[key], value >= old else { continue }
            let delta = Double(value - old)
            result[key + "_delta"] = delta
            if key == "ios_bytes_read" || key == "ios_network_bytes" {
                let rate = delta / elapsed
                if rate.isFinite { result[key + "_per_second"] = rate }
            }
        }
        previous = next; previousTime = time
        return result
    }
}
