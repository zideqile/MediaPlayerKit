import Foundation

/// One observed resource request, delivered on the main thread at completion.
/// Missing measurements stay nil; timestamps and elapsed are milliseconds.
public struct PlayerRequestEvent {
    public let url: String
    public let startAt: Double?
    public let endAt: Double?
    public let elapsed: Double?
    public let size: Int64?
    public let status: Int?
    public let kind: String
    public let cached: Bool
    public let errorCode: Int?
    public let errorDomain: String?

    public init(url: String, startAt: Double? = nil, endAt: Double? = nil,
                elapsed: Double? = nil, size: Int64? = nil, status: Int? = nil,
                kind: String = "media", cached: Bool = false,
                errorCode: Int? = nil, errorDomain: String? = nil) {
        self.url = url; self.startAt = startAt; self.endAt = endAt
        self.elapsed = elapsed; self.size = size; self.status = status
        self.kind = kind; self.cached = cached
        self.errorCode = errorCode; self.errorDomain = errorDomain
    }
}
