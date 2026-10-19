import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// What the debug tools want done to one request: wait, block, fail, or answer with another body.
///
/// A platform provider computes it from the rules the user set (on Android they live in the Kotlin
/// tools), and `NetworkInjection.apply` carries it out around the host's real transport call.
public struct NetworkInjectionDecision: Codable, Sendable, Equatable {
    public struct Failure: Codable, Sendable, Equatable {
        /// `timeout`, `connectionLost`, `notConnectedToInternet`, `cannotFindHost`, `dnsLookupFailed`,
        /// `httpError`, `sslError`, `cancelled` or `custom`.
        public var kind: String
        public var statusCode: Int?
        public var domain: String
        public var code: Int
        public var message: String

        public init(kind: String, statusCode: Int? = nil, domain: String = "", code: Int = 0, message: String = "") {
            self.kind = kind
            self.statusCode = statusCode
            self.domain = domain
            self.code = code
            self.message = message
        }
    }

    public struct Rewrite: Codable, Sendable, Equatable {
        public var statusCode: Int?
        public var body: String
        /// Answer without sending the request at all.
        public var shortCircuit: Bool

        public init(statusCode: Int? = nil, body: String, shortCircuit: Bool) {
            self.statusCode = statusCode
            self.body = body
            self.shortCircuit = shortCircuit
        }
    }

    public var delaySeconds: Double
    public var isBlocked: Bool
    public var failure: Failure?
    public var rewrite: Rewrite?

    public init(delaySeconds: Double = 0, isBlocked: Bool = false, failure: Failure? = nil, rewrite: Rewrite? = nil) {
        self.delaySeconds = delaySeconds
        self.isBlocked = isBlocked
        self.failure = failure
        self.rewrite = rewrite
    }

    public var isNoop: Bool {
        delaySeconds <= 0 && !isBlocked && failure == nil && rewrite == nil
    }
}

/// Applies delay, block, failure and response rewrite rules to requests a Swift transport sends.
///
/// iOS needs nothing here: the UIKit debugger injects through a URL protocol. On Android a Swift
/// `URLSession` never reaches OkHttp, so the host wraps its transport call in `apply` and the Android
/// tools supply a provider.
public enum NetworkInjection {
    public typealias Provider = @Sendable (_ url: String, _ method: String) -> NetworkInjectionDecision?

    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var provider: Provider?

        var current: Provider? {
            get { lock.lock(); defer { lock.unlock() }; return provider }
            set { lock.lock(); defer { lock.unlock() }; provider = newValue }
        }
    }

    private static let storage = Storage()

    /// Sets the provider asked about every request; `nil` turns injection off.
    public static func install(_ provider: Provider?) {
        storage.current = provider
    }

    /// Runs `perform` for `request`, honoring the current decision. With no provider or a no-op
    /// decision the real call runs untouched.
    public static func apply(
        to request: URLRequest,
        perform: (URLRequest) async throws -> (Data, URLResponse),
    ) async throws -> (Data, URLResponse) {
        guard let provider = storage.current,
              let url = request.url,
              let decision = provider(url.absoluteString, request.httpMethod ?? "GET"),
              !decision.isNoop
        else {
            return try await perform(request)
        }
        return try await carryOut(decision, for: request, url: url, perform: perform)
    }

    static func carryOut(
        _ decision: NetworkInjectionDecision,
        for request: URLRequest,
        url: URL,
        perform: (URLRequest) async throws -> (Data, URLResponse),
    ) async throws -> (Data, URLResponse) {
        if decision.delaySeconds > 0 {
            try await Task.sleep(nanoseconds: UInt64(min(decision.delaySeconds, 60) * 1_000_000_000))
        }
        if decision.isBlocked {
            return synthetic(url, status: 403, body: "Blocked by DebugSwift network rules.")
        }
        if let failure = decision.failure {
            if failure.kind == "httpError" {
                let status = failure.statusCode ?? 500
                let body = "{\"error\":\"Injected HTTP Error\",\"statusCode\":\(status),"
                    + "\"message\":\"This is a simulated HTTP \(status) error for testing purposes.\",\"injected\":true}"
                return synthetic(url, status: status, body: body)
            }
            throw error(for: failure)
        }
        if let rewrite = decision.rewrite, rewrite.shortCircuit {
            return synthetic(url, status: rewrite.statusCode ?? 200, body: rewrite.body)
        }
        let (data, response) = try await perform(request)
        guard let rewrite = decision.rewrite else { return (data, response) }
        let status = rewrite.statusCode ?? (response as? HTTPURLResponse)?.statusCode ?? 200
        return synthetic(url, status: status, body: rewrite.body, keeping: response as? HTTPURLResponse)
    }

    static func error(for failure: NetworkInjectionDecision.Failure) -> Error {
        let type: NetworkFailureConfig.FailureType = switch failure.kind {
        case "connectionLost": .connectionLost
        case "notConnectedToInternet": .notConnectedToInternet
        case "cannotFindHost": .cannotFindHost
        case "dnsLookupFailed": .dnsLookupFailed
        case "sslError": .sslError
        case "cancelled": .cancelled
        case "custom": .custom(domain: failure.domain, code: failure.code, description: failure.message)
        default: .timeout
        }
        return type.toError()
    }

    private static func synthetic(
        _ url: URL,
        status: Int,
        body: String,
        keeping original: HTTPURLResponse? = nil,
    ) -> (Data, URLResponse) {
        let data = Data(body.utf8)
        var headers: [String: String] = ["Content-Type": "application/json"]
        if let original {
            for (key, value) in original.allHeaderFields {
                if let key = key as? String, let value = value as? String { headers[key] = value }
            }
        }
        headers["Content-Length"] = String(data.count)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
        return (data, response ?? URLResponse(url: url, mimeType: "application/json", expectedContentLength: data.count, textEncodingName: nil))
    }
}
