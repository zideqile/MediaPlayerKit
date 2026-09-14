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
                             ("bandwidth", metrics.observedBitrate)] {
            if let value = value, value.isFinite, value >= 0,
               key == "fps" || value > 0 { result[key] = value }
        }
        let counters: [(deltaKey: String, rateKey: String?, value: Int64?)] = [
            ("read_bytes", "read_speed", metrics.bytesRead),
            ("net_bytes", "net_speed", metrics.networkBytes),
            ("drop", nil, metrics.droppedVideoFrames),
            ("drop_packet", nil, metrics.droppedVideoPackets),
            ("media_requests", nil, metrics.mediaRequests)
        ]
        let elapsed = previousTime.map { time - $0 }
        var next: [String: Int64] = [:]
        for counter in counters {
            guard let value = counter.value, value >= 0 else { continue }
            next[counter.deltaKey] = value
            guard let elapsed = elapsed, elapsed > 0,
                  let old = previous[counter.deltaKey], value >= old else { continue }
            let delta = Double(value - old)
            result[counter.deltaKey] = delta
            if let rateKey = counter.rateKey {
                let rate = delta / elapsed
                if rate.isFinite { result[rateKey] = rate }
            }
        }
        previous = next; previousTime = time
        return result
    }
}
