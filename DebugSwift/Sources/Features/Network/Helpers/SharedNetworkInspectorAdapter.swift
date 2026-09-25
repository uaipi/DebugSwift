//
//  SharedNetworkInspectorAdapter.swift
//  DebugSwift
//
//  Platform adapter used by the Skip SwiftUI network inspector.
//

import Foundation
import UIKit

public extension DebugSwift.Network {
    /// Encodes captured requests for the shared SwiftUI network inspector.
    @MainActor
    func sharedInspectorSnapshotJSON(featureID: String) -> String {
        let models = sharedInspectorModels(featureID: featureID)
        let requests: [[String: Any]] = models.map { model in
            if model.requestId == nil {
                model.requestId = UUID().uuidString
            }

            let duration = Double((model.totalDuration ?? "0").replacingOccurrences(of: " (s)", with: "")) ?? 0
            let requestHeaders = sharedInspectorHeaders(model.requestHeaderFields)
            let responseHeaders = sharedInspectorHeaders(model.responseHeaderFields)
            let requestBody = model.requestData ?? Data()
            let responseBody = model.responseData ?? Data()
            let decryptedBody = model.decryptedResponseData ?? Data()

            return [
                "id": model.requestId ?? UUID().uuidString,
                "url": model.url?.absoluteString ?? "",
                "method": model.method ?? "GET",
                "statusCode": model.statusCode ?? "0",
                "timestamp": model.startTime ?? "",
                "timestampMilliseconds": sharedInspectorTimestamp(model.startTime),
                "durationMilliseconds": Int((duration * 1_000).rounded()),
                "requestBytes": requestBody.count,
                "responseBytes": responseBody.count,
                "requestHeaders": requestHeaders,
                "responseHeaders": responseHeaders,
                "requestBody": String(data: requestBody, encoding: .utf8) ?? "",
                "responseBody": String(data: responseBody, encoding: .utf8) ?? "",
                "decryptedResponseBody": String(data: decryptedBody, encoding: .utf8) ?? "",
                "requestBodyBase64": requestBody.base64EncodedString(),
                "responseBodyBase64": responseBody.base64EncodedString(),
                "decryptedResponseBodyBase64": decryptedBody.base64EncodedString(),
                "mimeType": model.mineType ?? "",
                "error": model.errorLocalizedDescription ?? model.errorDescription ?? "",
                "graphqlOperation": sharedInspectorGraphQLOperation(model),
                "source": sharedInspectorIsWebView(model) ? "webview" : "http",
                "isSuccess": model.isSuccess
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: ["requests": requests]),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"requests\":[]}"
        }
        return json
    }

    /// Performs a platform action for one captured request or a whole feature.
    @MainActor
    func performSharedInspectorAction(featureID: String, actionID: String, requestID: String = "") -> String {
        let models = sharedInspectorModels(featureID: featureID)
        let model = models.first { $0.requestId == requestID }

        switch actionID {
        case "clear":
            let removedIDs = Set(models.compactMap(\.requestId))
            let datasource = HttpDatasource.shared
            datasource.httpModels.removeAll { removedIDs.contains($0.requestId ?? "") }
            for (index, request) in datasource.httpModels.enumerated() {
                request.index = index
            }
            NotificationCenter.default.post(name: NSNotification.Name("reloadHttp_DebugSwift"), object: nil)
            return "Request history cleared."
        case "delete":
            guard let model else { return "This request is no longer available." }
            HttpDatasource.shared.remove(model)
            NotificationCenter.default.post(name: NSNotification.Name("reloadHttp_DebugSwift"), object: nil)
            return "Request removed."
        case "copy_url":
            guard let model, let url = model.url?.absoluteString else { return "This request is no longer available." }
            UIPasteboard.general.string = url
            return "URL copied."
        case "copy_log":
            guard let model else { return "This request is no longer available." }
            let text = sharedInspectorLog(model)
            UIPasteboard.general.string = text
            return "Request log copied."
        case "share_log":
            guard let model else { return "This request is no longer available." }
            FileSharingManager.generateFileAndShare(text: sharedInspectorLog(model), fileName: "debugswift-request")
            return "Sharing request log."
        case "copy_curl":
            guard let model else { return "This request is no longer available." }
            _ = HARExportAdapter.copyCURL(model)
            return "cURL copied."
        case "export_har":
            guard !models.isEmpty else { return "There are no requests to export." }
            HARExportAdapter.exportHAR(models)
            return "Sharing HAR export."
        case "replay":
            guard let model, let url = model.url else { return "This request is no longer available." }
            var request = URLRequest(url: url)
            request.httpMethod = model.method ?? "GET"
            model.requestHeaderFields?.forEach { key, value in
                if let stringValue = value as? String {
                    request.setValue(stringValue, forHTTPHeaderField: key)
                }
            }
            request.httpBody = model.requestData
            URLSession.shared.dataTask(with: request).resume()
            return "Request replay started. Its response will appear in the request list."
        default:
            return "Unknown network action: \(actionID)."
        }
    }

    // MARK: - Private helpers

    private func sharedInspectorModels(featureID: String) -> [HttpModel] {
        let allModels = HttpDatasource.shared.httpModels
        for model in allModels where model.requestId == nil {
            model.requestId = UUID().uuidString
        }
        switch featureID {
        case "webview_network":
            return allModels.filter(sharedInspectorIsWebView)
        case "graphql":
            return allModels.filter { !sharedInspectorIsWebView($0) && GraphQLInspectorAdapter.isGraphQL($0) }
        default:
            return allModels.filter { !sharedInspectorIsWebView($0) }
        }
    }

    private func sharedInspectorIsWebView(_ model: HttpModel) -> Bool {
        model.responseHeaderFields?.first { $0.key.caseInsensitiveCompare("X-DebugSwift-Source") == .orderedSame }?.value as? String == "WKWebView"
    }

    private func sharedInspectorHeaders(_ headers: [String: Any]?) -> [String: String] {
        (headers ?? [:]).mapValues { String(describing: $0) }
    }

    private func sharedInspectorTimestamp(_ value: String?) -> Int64 {
        guard let value else { return 0 }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return Int64((formatter.date(from: value)?.timeIntervalSince1970 ?? 0) * 1_000)
    }

    private func sharedInspectorGraphQLOperation(_ model: HttpModel) -> String {
        guard let operation = GraphQLInspectorAdapter.detail(for: model).operation else { return "" }
        switch operation {
        case .query(let name): return name.map { "Query: \($0)" } ?? "Query"
        case .mutation(let name): return name.map { "Mutation: \($0)" } ?? "Mutation"
        case .subscription(let name): return name.map { "Subscription: \($0)" } ?? "Subscription"
        }
    }

    private func sharedInspectorLog(_ model: HttpModel) -> String {
        func bodyText(_ data: Data?) -> String {
            guard let data, !data.isEmpty else { return "No data" }
            return String(data: data, encoding: .utf8) ?? "<binary data: \(data.count) bytes>"
        }
        func headerText(_ headers: [String: Any]?) -> String {
            guard let headers, !headers.isEmpty else { return "No data" }
            return headers.keys.sorted().map { "\($0): \(String(describing: headers[$0]!))" }.joined(separator: "\n")
        }
        return """
        [\(model.method ?? "GET")] \(model.startTime ?? "") (\(model.statusCode ?? ""))

        ------- URL -------
        \(model.url?.absoluteString ?? "No data")

        ------- REQUEST HEADER -------
        \(headerText(model.requestHeaderFields))

        ------- REQUEST -------
        \(bodyText(model.requestData))

        ------- RESPONSE HEADER -------
        \(headerText(model.responseHeaderFields))

        ------- RESPONSE -------
        \(bodyText(model.decryptedResponseData ?? model.responseData))

        ------- TOTAL TIME -------
        \(model.totalDuration ?? "No data")

        ------- MIME TYPE -------
        \(model.mineType ?? "No data")
        """
    }
}
