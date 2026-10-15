import Foundation

/// Bounded, thread-safe store of recent HTTP exchanges.
///
/// Stack-agnostic on purpose: anything that can describe a finished request can feed it,
/// so the same inspector works on iOS and Android with `URLSession`, OkHttp, or a custom
/// transport. Sensitive headers are masked on ingestion, so credentials never sit in memory
/// or reach an export.
public actor NetworkRecorder {
    public static let shared = NetworkRecorder()

    public static let defaultCapacity = 500
    public static let defaultBodyLimit = 256 * 1024

    private let capacity: Int
    private let bodyLimit: Int
    private let redactedKeys: Set<String>
    private var records: [NetworkRecord] = []
    private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]

    /// - Parameters:
    ///   - capacity: Most recent records kept; older ones are dropped first.
    ///   - bodyLimit: Bytes kept per request or response body; longer bodies are truncated.
    ///   - redactedHeaders: Header names masked on ingestion, compared case-insensitively.
    public init(
        capacity: Int = NetworkRecorder.defaultCapacity,
        bodyLimit: Int = NetworkRecorder.defaultBodyLimit,
        redactedHeaders: Set<String> = HAREncoder.defaultRedactedKeys
    ) {
        self.capacity = max(1, capacity)
        self.bodyLimit = max(0, bodyLimit)
        redactedKeys = Set(redactedHeaders.map { $0.lowercased() })
    }

    public func record(_ record: NetworkRecord) {
        records.append(sanitized(record))
        if records.count > capacity {
            records.removeFirst(records.count - capacity)
        }
        notifyObservers()
    }

    /// Records oldest first.
    public func snapshot() -> [NetworkRecord] {
        records
    }

    public func clear() {
        guard !records.isEmpty else { return }
        records.removeAll()
        notifyObservers()
    }

    public func harCaptures() -> [HARCapture] {
        records.map(\.harCapture)
    }

    public func harJSON(pretty: Bool = true) -> String? {
        HAREncoder.encodeJSON(harCaptures(), pretty: pretty)
    }

    /// Emits once per change, coalescing bursts. Re-read `snapshot()` after each value.
    public func changes() -> AsyncStream<Void> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func notifyObservers() {
        for continuation in observers.values {
            continuation.yield()
        }
    }

    private func sanitized(_ record: NetworkRecord) -> NetworkRecord {
        let outcome: NetworkRecord.Outcome
        switch record.outcome {
        case let .response(statusCode, headers, body):
            outcome = .response(statusCode: statusCode, headers: redact(headers), body: truncated(body))
        case .failure:
            outcome = record.outcome
        }
        return NetworkRecord(
            id: record.id,
            startedAt: record.startedAt,
            duration: record.duration,
            method: record.method,
            url: record.url,
            requestHeaders: redact(record.requestHeaders),
            requestBody: truncated(record.requestBody),
            outcome: outcome
        )
    }

    private func redact(_ headers: [String: String]) -> [String: String] {
        headers.reduce(into: [:]) { result, pair in
            result[pair.key] = redactedKeys.contains(pair.key.lowercased()) ? "<redacted>" : pair.value
        }
    }

    private func truncated(_ body: Data?) -> Data? {
        guard let body, body.count > bodyLimit else { return body }
        return body.prefix(bodyLimit)
    }
}
