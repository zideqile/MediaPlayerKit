import Foundation

/// Navigation start closes the gate; only a committed document may handshake again.
struct BridgePageGate {
    private(set) var generation: UInt64 = 0
    private(set) var pageID: String?
    private(set) var navigating = false

    mutating func invalidate() {
        generation &+= 1
        navigating = true
        pageID = nil
    }
    mutating func commit() {
        generation &+= 1
        navigating = false
        pageID = nil
    }
    mutating func accept(_ token: String?, handshake: Bool, generation expected: UInt64) -> Bool {
        guard expected == generation, !navigating else { return false }
        if let token = token {
            guard !token.isEmpty else { return false }
            if handshake { pageID = token }
            return pageID == token
        }
        // Legacy pages remain supported, but cannot downgrade an established modern session.
        return pageID == nil
    }
}
