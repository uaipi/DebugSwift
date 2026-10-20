import DebugSwiftCore
import Foundation

/// Hands every request the Swift networking stack records to the Kotlin network tools.
///
/// Swift's URLSession does not run through OkHttp, so the OkHttp interceptor never sees it. The
/// shared `NetworkRecorder` does, so this watches it and forwards each new exchange once.
enum DebugSwiftNetworkForwarder {
    #if os(Android)
        private struct Payload: Encodable {
            let method: String
            let url: String
            let status: Int
            let durationMs: Int
            let requestBytes: Int
            let responseBytes: Int
            let requestBody: String
            let responseBody: String
            let error: String
            let requestHeaders: [String: String]
            let responseHeaders: [String: String]
        }

        /// The task that watches the recorder; started once for the process.
        private static let task: Task<Void, Never> = Task.detached {
            var forwarded = Set<UUID>()
            // Subscribe before the first read so nothing recorded in between is missed.
            let changes = await NetworkRecorder.shared.changes()
            await forwardNew(into: &forwarded)
            for await _ in changes {
                await forwardNew(into: &forwarded)
            }
        }

        private static func forwardNew(into forwarded: inout Set<UUID>) async {
            let records = await NetworkRecorder.shared.snapshot()
            forwarded.formIntersection(records.map(\.id))
            for record in records where !forwarded.contains(record.id) {
                forwarded.insert(record.id)
                forward(record)
            }
        }

        static func start() {
            _ = task
            // Rules set in the Android tools apply to Swift requests the host sends through
            // `NetworkInjection.apply`.
            NetworkInjection.install { url, method in
                let json = DebugSwiftNativeBridge.injectionDecision(url, method)
                guard let data = json.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(NetworkInjectionDecision.self, from: data)
            }
        }

        private static func forward(_ record: NetworkRecord) {
            let payload = Payload(
                method: record.method,
                url: record.url,
                status: record.statusCode ?? 0,
                durationMs: Int(record.duration * 1000),
                requestBytes: record.requestBody?.count ?? 0,
                responseBytes: record.responseBody?.count ?? 0,
                requestBody: text(record.requestBody),
                responseBody: text(record.responseBody),
                error: failureDescription(record),
                requestHeaders: record.requestHeaders,
                responseHeaders: responseHeaders(record),
            )
            guard let data = try? JSONEncoder().encode(payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            DebugSwiftNativeBridge.recordExternalNetwork(json)
        }

        private static func text(_ body: Data?) -> String {
            guard let body, !body.isEmpty else { return "" }
            return String(data: body, encoding: .utf8) ?? "(binary, \(body.count) bytes)"
        }

        private static func failureDescription(_ record: NetworkRecord) -> String {
            if case let .failure(description) = record.outcome { description } else { "" }
        }

        private static func responseHeaders(_ record: NetworkRecord) -> [String: String] {
            if case let .response(_, headers, _) = record.outcome { headers } else { [:] }
        }
    #else
        static func start() {}
    #endif
}
