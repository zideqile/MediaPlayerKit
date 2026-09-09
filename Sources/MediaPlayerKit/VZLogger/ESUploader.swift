import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Injectable transport allows contract tests without contacting the log servers.
public protocol LogHTTPTransport: AnyObject {
    func send(_ request: URLRequest, completion: @escaping (Result<Data, Error>) -> Void)
}
public final class URLSessionLogTransport: LogHTTPTransport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func send(_ request: URLRequest, completion: @escaping (Result<Data, Error>) -> Void) {
        session.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                completion(.failure(URLError(.badServerResponse))); return
            }
            completion(.success(data ?? Data()))
        }.resume()
    }
}
public protocol ESUploader: AnyObject {
    func upload(record: [String: Any], completion: @escaping (Bool) -> Void)
}
public final class OldESUploader: ESUploader {
    private let url: URL
    private let transport: LogHTTPTransport
    public init(server: LogServerConfig, env: String, buryContentName: String = "VPlayerLog", transport: LogHTTPTransport = URLSessionLogTransport()) throws {
        var components = URLComponents()
        components.scheme = server.secure ? "https" : "http"
        components.host = server.domain; components.port = server.port
        components.path = server.path.hasPrefix("/") ? server.path : "/" + server.path
        components.queryItems = [URLQueryItem(name: "bury_content", value: "stream_\(buryContentName)-\(env.lowercased())_stat")]
        guard let url = components.url else { throw URLError(.badURL) }
        self.url = url; self.transport = transport
    }
    public func upload(record: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let body = try? JSONSerialization.data(withJSONObject: [record]) else { completion(false); return }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        transport.send(request) { result in
            if case .success = result { completion(true) } else { completion(false) }
        }
    }
}

/// Resolves a signed type=2 upload URL and refreshes it at half its server-provided lifetime.
public final class NewESUploader: ESUploader {
    private let stateLock = NSLock()
    private let lookupQueue = DispatchQueue(label: "com.mediaplayerkit.newesuploader.lookup", qos: .utility)
    private let lookupURL: URL
    private let authorization: () -> String
    private let transport: LogHTTPTransport
    private var uploadURL: URL?
    private var refreshAt = Date.distantPast
    private var isLookingUp = false
    private var pendingUploads: [(Data, (Bool) -> Void)] = []

    public var cachedRefreshAt: Date {
        stateLock.lock(); defer { stateLock.unlock() }
        return refreshAt
    }

    public init(env: String, topicId: String, userId: String, streamId: String, clusterDomain: String,
                authorization: @escaping () -> String, transport: LogHTTPTransport = URLSessionLogTransport()) throws {
        let prefix = ["prod": "lg", "pre": "lg-pre", "test": "lg-test"][env] ?? "lg-dev"
        var components = URLComponents()
        components.scheme = "https"; components.host = "\(prefix).\(clusterDomain)"
        components.path = "/log/usertrack_list"
        components.queryItems = [URLQueryItem(name: "topicId", value: topicId), URLQueryItem(name: "userId", value: userId), URLQueryItem(name: "streamId", value: streamId)]
        guard let url = components.url else { throw URLError(.badURL) }
        lookupURL = url; self.authorization = authorization; self.transport = transport
    }

    public func upload(record: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let body = try? JSONSerialization.data(withJSONObject: record) else { completion(false); return }
        stateLock.lock()
        if Date() < refreshAt, let url = uploadURL {
            stateLock.unlock()
            post(body, to: url, completion: completion)
            return
        }
        pendingUploads.append((body, completion))
        if isLookingUp {
            stateLock.unlock()
            return
        }
        isLookingUp = true
        stateLock.unlock()

        lookupQueue.async { [weak self] in
            guard let self = self else { return }
            let token = self.authorization()
            var request = URLRequest(url: self.lookupURL, timeoutInterval: 5)
            request.setValue(token, forHTTPHeaderField: "Authorization")
            self.transport.send(request) { [weak self] result in
                guard let self = self else { return }
                var resolvedURL: URL?
                var resolvedRefreshAt = Date.distantPast
                var success = false

                if case let .success(data) = result,
                   let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                   json["isok"] as? Bool == true, json["code"] as? Int == 0,
                   let items = json["dataObj"] as? [[String: Any]],
                   let item = items.first(where: { $0["type"] as? Int == 2 }),
                   let text = item["url"] as? String, let url = URL(string: text),
                   ["http", "https"].contains(url.scheme ?? ""), url.host != nil,
                   let expires = item["expires"] as? Double, let now = item["now"] as? Double,
                   expires > now {
                    let isMilliseconds = now > 10_000_000_000 || expires > 10_000_000_000
                    let diffSeconds = isMilliseconds ? (expires - now) / 1000.0 : (expires - now)
                    resolvedURL = url
                    resolvedRefreshAt = Date().addingTimeInterval(diffSeconds / 2)
                    success = true
                }

                self.stateLock.lock()
                self.isLookingUp = false
                if success {
                    self.uploadURL = resolvedURL
                    self.refreshAt = resolvedRefreshAt
                }
                let pending = self.pendingUploads
                self.pendingUploads.removeAll()
                self.stateLock.unlock()

                for (pendingBody, pendingCompletion) in pending {
                    if let targetURL = resolvedURL {
                        self.post(pendingBody, to: targetURL, completion: pendingCompletion)
                    } else {
                        pendingCompletion(false)
                    }
                }
            }
        }
    }

    private func post(_ data: Data, to url: URL, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"; request.httpBody = data
        request.setValue("text/plain; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        transport.send(request) { [weak self] result in
            if case .success = result {
                completion(true)
            } else {
                self?.stateLock.lock()
                self?.refreshAt = .distantPast
                self?.stateLock.unlock()
                completion(false)
            }
        }
    }
}

/// One in-flight upload; a bounded pending queue; nonblocking retries at 1/2/3 seconds.
public final class StatisticsUploadTask {
    private let executor = LogExecutor()
    private let uploader: ESUploader
    private let capacity: Int
    private var records: [[String: Any]] = []
    private var busy = false
    private var closed = false
    private var retry = 0
    private var draining = false
    private var drainCompletion: (@Sendable () -> Void)?
    private var dropped = 0
    public var innerDrop: Int { executor.sync { dropped } }
    public init(uploader: ESUploader, capacity: Int = 10) {
        self.uploader = uploader; self.capacity = max(1, capacity)
    }
    public func upload(_ record: [String: Any]) {
        executor.sync {
            guard !closed, !draining else { return }
            if records.count >= capacity { records.removeFirst(); dropped += 1 }
            records.append(record)
            sendNext()
        }
    }
    private func sendNext() {
        guard !closed, !busy, !records.isEmpty else { return }
        busy = true
        let record = records.removeFirst()
        uploader.upload(record: record) { [weak self] success in
            guard let self = self else { return }
            self.executor.queue.async {
                guard !self.closed else { return }
                if success {
                    self.retry = 0; self.busy = false; self.sendNext(); self.completeDrainIfReady()
                } else {
                    if self.records.count >= self.capacity { self.records.removeLast(); self.dropped += 1 }
                    self.records.insert(record, at: 0)
                    self.retry = min(3, self.retry + 1)
                    self.executor.queue.asyncAfter(deadline: .now() + Double(self.retry)) { [weak self] in
                        self?.busy = false; self?.sendNext()
                    }
                }
            }
        }
    }
    /// Wait asynchronously for queued records, with a bounded shutdown deadline.
    public func finish(timeout: TimeInterval = 5, completion: @escaping @Sendable () -> Void) {
        executor.sync {
            guard !draining else { return }
            draining = true
            drainCompletion = completion
            if closed { completeDrain(); return }
            completeDrainIfReady()
            executor.queue.asyncAfter(deadline: .now() + max(0, timeout)) { [weak self] in
                self?.completeDrain()
            }
        }
    }
    private func completeDrainIfReady() {
        if draining && !busy && records.isEmpty { completeDrain() }
    }
    private func completeDrain() {
        guard let completion = drainCompletion else { return }
        drainCompletion = nil
        closed = true
        records.removeAll()
        DispatchQueue.global(qos: .utility).async(execute: completion)
    }
    /// Stops retries and drops pending records. An already submitted request may finish.
    public func stop() { executor.sync { closed = true; records.removeAll(); completeDrain() } }
}
