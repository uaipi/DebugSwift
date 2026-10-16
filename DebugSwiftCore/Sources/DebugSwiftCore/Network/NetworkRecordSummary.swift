import Foundation

/// A `NetworkRecord` shaped for display: host and path split, headers sorted, bodies formatted
/// and a ready-to-run cURL command. Kept in the Core so every UI shows the same thing.
public struct NetworkRecordSummary: Sendable, Equatable, Identifiable {
    public enum Status: Sendable, Equatable {
        case success
        case redirect
        case error
        case failed
    }

    public struct Header: Sendable, Equatable, Identifiable {
        public let name: String
        public let value: String
        public var id: String { name }
    }

    public let id: UUID
    public let method: String
    public let host: String
    public let path: String
    public let url: String
    public let startedAt: Date
    public let durationMilliseconds: Int
    public let statusCode: Int?
    public let status: Status
    public let failureDescription: String?
    public let requestHeaders: [Header]
    public let responseHeaders: [Header]
    public let requestBody: String?
    public let responseBody: String?
    public let curlCommand: String

    public var statusTitle: String {
        if let statusCode { String(statusCode) } else { "—" }
    }

    public var searchableText: String {
        "\(method) \(url) \(statusTitle)".lowercased()
    }

    public init(record: NetworkRecord) {
        let components = URLComponents(string: record.url)
        let query = components?.percentEncodedQuery.map { "?\($0)" } ?? ""
        var responseHeaders: [String: String] = [:]
        var failure: String?
        switch record.outcome {
        case let .response(_, headers, _): responseHeaders = headers
        case let .failure(description): failure = description
        }
        id = record.id
        method = record.method
        host = components?.host ?? record.url
        path = (components?.percentEncodedPath ?? "") + query
        url = record.url
        startedAt = record.startedAt
        durationMilliseconds = Int((record.duration * 1000).rounded())
        statusCode = record.statusCode
        status = Self.status(for: record.statusCode)
        failureDescription = failure
        requestHeaders = Self.headers(record.requestHeaders)
        self.responseHeaders = Self.headers(responseHeaders)
        requestBody = Self.formattedBody(record.requestBody)
        responseBody = Self.formattedBody(record.responseBody)
        curlCommand = HAREncoder.curlCommand(for: record.harCapture)
    }

    private static func status(for statusCode: Int?) -> Status {
        guard let statusCode else { return .failed }
        switch statusCode {
        case 200 ..< 300: return .success
        case 300 ..< 400: return .redirect
        default: return .error
        }
    }

    private static func headers(_ headers: [String: String]) -> [Header] {
        headers
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { Header(name: $0.key, value: $0.value) }
    }

    private static func formattedBody(_ data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8)
        {
            return text
        }
        return String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
    }
}
