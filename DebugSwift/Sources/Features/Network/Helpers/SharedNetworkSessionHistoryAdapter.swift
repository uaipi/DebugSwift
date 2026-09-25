//
// SharedNetworkSessionHistoryAdapter.swift
// DebugSwift
//

import Foundation

#if canImport(SwiftData)
import SwiftData

@available(iOS 17.0, *)
@MainActor
public extension DebugSwift.Network {
    func sharedSessionHistorySnapshotJSON() async -> String {
        let manager = NetworkSessionPersistenceManager.shared
        let sessions = await manager.fetchSessions()
        let activeSessionID = await manager.activeSessionID()
        let records: [[String: Any]] = sessions.map { session in
            let endedAt: Any
            if let date = session.endedAt {
                endedAt = Int64(date.timeIntervalSince1970 * 1_000)
            } else {
                endedAt = NSNull()
            }
            return [
                "id": session.id.uuidString,
                "startedAtMilliseconds": Int64(session.startedAt.timeIntervalSince1970 * 1_000),
                "endedAtMilliseconds": endedAt,
                "requestCount": session.requestCount,
                "isActive": session.id == activeSessionID
            ]
        }
        return Self.sharedSessionJSON(["sessions": records, "retentionDays": NetworkSessionPersistenceManager.retentionDaysPreference])
    }

    func sharedSessionRequestsSnapshotJSON(sessionID: String) async -> String {
        guard let id = UUID(uuidString: sessionID) else { return "{\"requests\":[]}" }
        let requests = await NetworkSessionPersistenceManager.shared.fetchRequests(for: id)
        let rows: [[String: Any]] = requests.map { request in
            let model = request.makeHttpModel()
            let duration = Double((model.totalDuration ?? "0").replacingOccurrences(of: " (s)", with: "")) ?? 0
            let requestData = model.requestData ?? Data()
            let responseData = model.responseData ?? Data()
            let requestHeaders = Self.sharedHistoryHeaders(model.requestHeaderFields)
            let responseHeaders = Self.sharedHistoryHeaders(model.responseHeaderFields)
            let timestamp = model.startTime ?? ""
            return [
                "id": request.id.uuidString,
                "url": model.url?.absoluteString ?? "",
                "method": model.method ?? "GET",
                "statusCode": model.statusCode ?? "0",
                "timestamp": timestamp,
                "timestampMilliseconds": Self.sharedHistoryTimestamp(timestamp),
                "durationMilliseconds": Int((duration * 1_000).rounded()),
                "requestBytes": requestData.count,
                "responseBytes": responseData.count,
                "requestHeaders": requestHeaders,
                "responseHeaders": responseHeaders,
                "requestBody": String(data: requestData, encoding: .utf8) ?? "",
                "responseBody": String(data: responseData, encoding: .utf8) ?? "",
                "decryptedResponseBody": "",
                "requestBodyBase64": requestData.base64EncodedString(),
                "responseBodyBase64": responseData.base64EncodedString(),
                "decryptedResponseBodyBase64": "",
                "mimeType": model.mineType ?? "",
                "error": model.errorLocalizedDescription ?? model.errorDescription ?? "",
                "graphqlOperation": Self.sharedHistoryGraphQLOperation(model),
                "source": "http",
                "isSuccess": model.isSuccess
            ]
        }
        return Self.sharedSessionJSON(["requests": rows])
    }

    func performSharedSessionHistoryAction(actionID: String, sessionID: String = "") async -> String {
        let manager = NetworkSessionPersistenceManager.shared
        switch actionID {
        case "clear_all":
            await manager.deleteAllSessions()
            return "All saved network sessions were cleared."
        case "delete_session":
            guard let id = UUID(uuidString: sessionID) else { return "This session is no longer available." }
            await manager.deleteSession(id: id)
            return "Network session deleted."
        case "import_session":
            guard let id = UUID(uuidString: sessionID) else { return "This session is no longer available." }
            let requests = await manager.fetchRequests(for: id)
            let rules = NetworkSessionRewriteRuleBuilder.makeRules(from: requests.map { $0.makeHttpModel() })
            NetworkInjectionManager.shared.replaceRewriteRulesFromSessionHistory(rules)
            return "Replaced existing Response Modifier rules with \(rules.count) rule(s) from this session. Response Modifier is now active."
        default:
            return "Unknown session history action: \(actionID)."
        }
    }

    func shareSharedSessionRequestLog(_ text: String) -> String {
        FileSharingManager.generateFileAndShare(text: text, fileName: "debugswift-request")
        return "Sharing request log."
    }

    func replaySharedSessionRequest(id requestID: String) async -> String {
        guard let requestUUID = UUID(uuidString: requestID) else { return "This request is no longer available." }
        let manager = NetworkSessionPersistenceManager.shared
        let sessions = await manager.fetchSessions()
        var requestRecord: NetworkSessionPersistenceManager.RequestRecord?
        for session in sessions {
            let requests = await manager.fetchRequests(for: session.id)
            if let match = requests.first(where: { $0.id == requestUUID }) {
                requestRecord = match
                break
            }
        }
        guard let requestRecord,
              let urlString = requestRecord.url,
              let url = URL(string: urlString) else { return "This request is no longer available." }
        var request = URLRequest(url: url)
        request.httpMethod = requestRecord.method ?? "GET"
        if let headers = NetworkSessionPersistenceManager.decodeHeaders(requestRecord.requestHeadersData) {
            headers.forEach { key, value in
                if let stringValue = value as? String { request.setValue(stringValue, forHTTPHeaderField: key) }
            }
        }
        request.httpBody = requestRecord.requestData
        URLSession.shared.dataTask(with: request).resume()
        return "Request replay started. Its response will appear in the request list."
    }

    private static func sharedSessionJSON(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    private static func sharedHistoryHeaders(_ headers: [String: Any]?) -> [String: String] {
        (headers ?? [:]).mapValues { String(describing: $0) }
    }

    private static func sharedHistoryTimestamp(_ value: String) -> Int64 {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return Int64((formatter.date(from: value)?.timeIntervalSince1970 ?? 0) * 1_000)
    }

    private static func sharedHistoryGraphQLOperation(_ model: HttpModel) -> String {
        guard let operation = GraphQLInspectorAdapter.detail(for: model).operation else { return "" }
        switch operation {
        case .query(let name): return name.map { "Query: \($0)" } ?? "Query"
        case .mutation(let name): return name.map { "Mutation: \($0)" } ?? "Mutation"
        case .subscription(let name): return name.map { "Subscription: \($0)" } ?? "Subscription"
        }
    }
}
#endif
