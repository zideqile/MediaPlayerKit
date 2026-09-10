import Foundation
import AVFoundation
@_implementationOnly import KSPlayer

/// Platform-specific classification is isolated from the portable recovery policy.
enum PlaybackErrorAdapters {
    static func classify(_ error: NSError, depth: Int = 0) -> PlaybackErrorCategory {
        guard depth < 16 else { return .unknown }
        let portable = PlaybackErrorClassifier.classify(error)
        if portable != .unknown { return portable }
        if let ffmpeg = error.userInfo[NSUnderlyingErrorKey] as? KSPlayer.AVError {
            switch ffmpeg {
            case .httpNotFound: return .sourceNotFound
            case .httpUnauthorized, .httpForbidden: return .authorization
            case .httpServerError: return .network
            case .decoderNotFound, .invalidData: return .decoding
            case .protocolNotFound: return .invalidSource
            default: break
            }
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error {
            let category = classify(underlying as NSError, depth: depth + 1)
            if category != .unknown { return category }
        }
        if error.domain == AVFoundationErrorDomain {
            switch AVFoundation.AVError.Code(rawValue: error.code) {
            case .decoderNotFound, .decodeFailed, .fileFormatNotRecognized: return .decoding
            case .contentIsNotAuthorized, .applicationIsNotAuthorized: return .authorization
            default: break
            }
        }
        if error.domain == KSPlayerErrorDomain, let code = KSPlayerErrorCode(rawValue: error.code) {
            switch code {
            case .codecContextFindDecoder, .codesContextOpen, .codecVideoSendPacket,
                 .codecAudioSendPacket, .codecVideoReceiveFrame, .codecAudioReceiveFrame,
                 .videoTracksUnplayable: return .decoding
            default: break
            }
        }
        return .unknown
    }
}
