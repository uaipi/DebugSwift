import Foundation

/// A finished HTTP exchange, independent of any networking stack or UI framework.
///
/// Producers (a `URLProtocol`, an app-level transport decorator, an OkHttp interceptor
/// bridge) build one of these when a request completes and hand it to `NetworkRecorder`.
public struct NetworkRecord: Sendable, Equatable, Identifiable {
    public enum Outcome: Sendable, Equatable {
        case response(statusCode: Int, headers: [String: String], body: Data?)
        case failure(description: String)
    }

    public let id: UUID
    public let startedAt: Date
    public let duration: TimeInterval
    public let method: String
    public let url: String
    public let requestHeaders: [String: String]
    public let requestBody: Data?
    public let outcome: Outcome

    public init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        duration: TimeInterval,
        method: String,
        url: String,
        requestHeaders: [String: String] = [:],
        requestBody: Data? = nil,
        outcome: Outcome
    ) {
        self.id = id
        self.startedAt = startedAt
        self.duration = duration
        self.method = method
        self.url = url
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.outcome = outcome
    }

    public var statusCode: Int? {
        if case let .response(statusCode, _, _) = outcome { statusCode } else { nil }
    }

    public var isSuccess: Bool {
        guard let statusCode else { return false }
        return (200..<400).contains(statusCode)
    }

    public var responseBody: Data? {
        if case let .response(_, _, body) = outcome { body } else { nil }
    }
}

public extension NetworkRecord {
    /// The HAR view of this record. Failures export as status 0 with the error as body.
    var harCapture: HARCapture {
        let request = HARRequest(
            method: method,
            url: url,
            headers: requestHeaders,
            body: requestBody.flatMap { String(data: $0, encoding: .utf8) }
        )
        let response: HARResponse
        switch outcome {
        case let .response(statusCode, headers, body):
            response = HARResponse(
                status: statusCode,
                headers: headers,
                body: body.flatMap { String(data: $0, encoding: .utf8) }
            )
        case let .failure(description):
            response = HARResponse(status: 0, headers: [:], body: description)
        }
        return HARCapture(
            request: request,
            response: response,
            startedDateTime: startedAt,
            time: duration * 1000
        )
    }
}
