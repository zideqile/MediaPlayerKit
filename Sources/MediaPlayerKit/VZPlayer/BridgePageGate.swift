import Foundation

/// Navigation start closes the gate; only a committed document may handshake again.
struct BridgePageGate {
    private(set) var generation: UInt64 = 0
    private(set) var pageID: String?
    private(set) var navigating = false

    var strict = false

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
        // In strict mode, an established modern session requires pageId on all messages.
        // In default compatible mode, legacy callers without pageId can coexist without clearing the session.
        if strict {
            return pageID == nil
        }
        return true
    }
}
