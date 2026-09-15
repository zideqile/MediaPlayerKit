import Foundation

/// Main-thread watchdog. Deadlines use a monotonic clock and never depend on progress callbacks.
struct PlaybackWatchdog {
    enum Phase: String { case startup, buffering, frozen }
    private var started = false
    private var advanced = false
    private var position: TimeInterval = 0
    private var phase: Phase?
    private var since: TimeInterval?
    private var fired = false

    mutating func begin(position: TimeInterval = 0) {
        self = PlaybackWatchdog()
        self.position = position.isFinite ? position : 0
    }
    mutating func progress(_ value: TimeInterval) {
        guard value.isFinite else { return }
        if value > position {
            if !started { rendered() }
            advanced = true
        }
        position = value
    }
    mutating func suspend() { phase = nil; since = nil; advanced = false }
    mutating func rendered() { started = true; suspend() }

    mutating func check(at now: TimeInterval, state: PlayerState, enabled: Bool,
                        startupMs: Int, bufferingMs: Int) -> Phase? {
        guard !fired, now.isFinite else { return nil }
        guard enabled, state != .completed, state != .stopped, state != .error else {
            suspend(); return nil
        }
        let moved = advanced
        advanced = false
        let next: Phase?
        if !started { next = .startup }
        else if state == .buffering || state == .preparing || state == .readyToPlay { next = .buffering }
        else if state == .playing && !moved { next = .frozen }
        else { next = nil }
        guard let next = next else { suspend(); return nil }
        let limit = next == .startup ? startupMs : bufferingMs
        guard limit > 0 else { suspend(); return nil }
        if phase != next || since == nil { phase = next; since = now }
        guard let since = since, now - since >= Double(limit) / 1000 else { return nil }
        fired = true
        return next
    }
}
