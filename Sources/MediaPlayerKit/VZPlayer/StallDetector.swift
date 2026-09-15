import Foundation

/// Completed live stalls in a monotonic sliding window. Check on the next buffering entry,
/// matching vplayer; the independent watchdog handles a single never-ending stall.
struct StallDetector {
    private struct Sample { let end: Double; let duration: Double }
    private var samples: [Sample] = []
    private var since: Double?
    private var totalDuration: Double = 0
    private var totalCount = 0
    private var fired = false

    mutating func reset() { self = StallDetector() }
    mutating func suspend() { since = nil }

    mutating func update(state: PlayerState, at now: TimeInterval, isLive: Bool,
                         allowed: Bool, policy: StalledSourceSwitchPolicy) -> [String: Any]? {
        guard policy.enable, isLive else { reset(); return nil }
        guard allowed, now.isFinite else { suspend(); return nil }
        guard !fired else { return nil }
        let time = now * 1000
        let window = Double(policy.slidingWindowInMs > 0 ? policy.slidingWindowInMs : 60000)
        samples.removeAll { time - $0.end > window }
        if state == .playing {
            if let start = since {
                let duration = max(0, time - start)
                let minimum = Double(policy.minStalledDurationThreshold > 0 ? policy.minStalledDurationThreshold : 200)
                if duration >= minimum {
                    samples.append(Sample(end: time, duration: duration))
                    totalDuration += duration; totalCount += 1
                }
            }
            since = nil
        } else if state == .buffering {
            guard since == nil else { return nil } // Duplicate state does not restart or double-count.
            since = time
            let duration = samples.reduce(0) { $0 + $1.duration }
            let maxDuration = Double(policy.maxStalledDurationInMsInSlidingWindowInMs > 0
                ? policy.maxStalledDurationInMsInSlidingWindowInMs : 6000)
            let maxCount = policy.maxStalledCountInSlidingWindowInMs > 0
                ? policy.maxStalledCountInSlidingWindowInMs : 3
            if duration > maxDuration || samples.count > maxCount {
                fired = true
                return ["stalledDurationInMsInSlidingWindowInMs": duration,
                        "stalledCountInSlidingWindowInMs": samples.count,
                        "totalStalledDuration": totalDuration, "totalStalledCount": totalCount]
            }
        } else { suspend() }
        return nil
    }
}
