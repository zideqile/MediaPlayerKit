import Foundation

@objc public enum PlaybackErrorCategory: Int {
    case unknown, sourceNotFound, invalidSource, network, timeout, authorization, decoding, cancelled
}
@objc public enum PlaybackRecoveryAction: Int {
    case nextEngine, nextSource, stop
}

/// Immutable record of one failed source/engine attempt. The original NSError is retained.
@objc public final class PlaybackAttemptFailure: NSObject {
    @objc public let sourceIndex: Int
    @objc public let sourceURL: String
    @objc public let engine: PlayerEngineType
    @objc public let category: PlaybackErrorCategory
    @objc public let error: NSError
    @objc public let action: PlaybackRecoveryAction
    public init(sourceIndex: Int, sourceURL: String, engine: PlayerEngineType,
                category: PlaybackErrorCategory, error: NSError, action: PlaybackRecoveryAction) {
        self.sourceIndex = sourceIndex; self.sourceURL = sourceURL; self.engine = engine
        self.category = category; self.error = error; self.action = action
        super.init()
    }
}

/// Pure decision logic; intentionally no network waits, timers, logging or player creation.
public enum PlaybackRecoveryPolicy {
    public static func action(for category: PlaybackErrorCategory, hasNextEngine: Bool, hasNextSource: Bool) -> PlaybackRecoveryAction {
        if category == .cancelled { return .stop }
        if category != .sourceNotFound && category != .invalidSource && hasNextEngine { return .nextEngine }
        return hasNextSource ? .nextSource : .stop
    }
}

public enum PlaybackErrorClassifier {
    /// Set by the engine adapter only when an actual HTTP response status is available.
    public static let httpStatusKey = "MediaPlayerKit.HTTPStatusCode"

    public static func classify(_ error: NSError) -> PlaybackErrorCategory {
        classify(error, depth: 0)
    }
    private static func classify(_ error: NSError, depth: Int) -> PlaybackErrorCategory {
        guard depth < 16 else { return .unknown }
        if let status = error.userInfo[httpStatusKey] as? Int {
            switch status {
            case 404, 410: return .sourceNotFound
            case 401, 403: return .authorization
            case 408, 504: return .timeout
            case 500...599: return .network
            default: break
            }
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error {
            let category = classify(underlying as NSError, depth: depth + 1)
            if category != .unknown { return category }
        }
        if error.domain == NSURLErrorDomain {
            switch error.code {
            case NSURLErrorCancelled: return .cancelled
            case NSURLErrorTimedOut: return .timeout
            case NSURLErrorBadURL, NSURLErrorUnsupportedURL: return .invalidSource
            case NSURLErrorFileDoesNotExist: return .sourceNotFound
            case NSURLErrorUserAuthenticationRequired, NSURLErrorUserCancelledAuthentication: return .authorization
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed,
                 NSURLErrorResourceUnavailable: return .network
            default: break
            }
        }
        // Never infer HTTP status from an arbitrary error code or a URL in the description.
        return .unknown
    }
}
