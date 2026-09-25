//
// SharedWebSocketInspectorAdapter.swift
// DebugSwift
//

import Foundation
import UIKit

public extension DebugSwift.WebSocket {
    /// Returns WebSocket connection metadata and frames for the shared SwiftUI inspector.
    @MainActor
    static func sharedInspectorSnapshotJSON(
        connectionID: String = "",
        query: String = "",
        direction: String = ""
    ) -> String {
        let connections = WebSocketDataSource.shared.getConnectionsSortedByActivity()
        let connectionRows: [[String: Any]] = connections.map { connection in
            let counts = Dictionary(grouping: connection.frames, by: { sharedFrameDirection($0.direction) })
            return [
                "id": connection.id,
                "url": connection.url.absoluteString,
                "name": connection.displayName,
                "status": connection.status.displayString,
                "statusDetail": sharedStatusDetail(connection.status),
                "createdAtMilliseconds": Int64(connection.createdAt.timeIntervalSince1970 * 1_000),
                "lastActivityAtMilliseconds": Int64(connection.lastActivityAt.timeIntervalSince1970 * 1_000),
                "frameCount": connection.frames.count,
                "sentCount": counts["Sent"]?.count ?? 0,
                "receivedCount": counts["Received"]?.count ?? 0,
                "unreadFrameCount": connection.unreadFrameCount
            ]
        }

        let frameRows: [[String: Any]]
        if let connection = connections.first(where: { $0.id == connectionID }) {
            let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            frameRows = connection.frames
                .sorted { $0.timestamp > $1.timestamp }
                .filter { frame in
                    (direction.isEmpty || sharedFrameDirection(frame.direction) == direction) &&
                        (normalizedQuery.isEmpty ||
                         (frame.payloadString ?? frame.hexDump).lowercased().contains(normalizedQuery))
                }
                .map { frame in
                    let payloadText = frame.payloadString
                    let prettyText = frame.prettyPrintedJSON ?? payloadText ?? ""
                    let hexLimit = min(frame.payload.count, 4_096)
                    let hex = frame.payload.prefix(hexLimit).map { String(format: "%02X", $0) }.joined(separator: " ")
                    return [
                        "id": frame.id,
                        "connectionID": frame.connectionId,
                        "timestampMilliseconds": Int64(frame.timestamp.timeIntervalSince1970 * 1_000),
                        "direction": sharedFrameDirection(frame.direction),
                        "type": sharedFrameType(frame.type),
                        "size": frame.payloadSize,
                        "payload": payloadText ?? "",
                        "prettyPayload": prettyText,
                        "payloadBase64": frame.payload.base64EncodedString(),
                        "hexDump": hex,
                        "hexTruncated": frame.payload.count > hexLimit
                    ]
                }
        } else {
            frameRows = []
        }

        guard let data = try? JSONSerialization.data(withJSONObject: [
            "connections": connectionRows,
            "frames": frameRows
        ]), let json = String(data: data, encoding: .utf8) else {
            return "{\"connections\":[],\"frames\":[]}"
        }
        return json
    }

    /// Runs native WebSocket actions requested by the shared SwiftUI inspector.
    @MainActor
    static func performSharedInspectorAction(
        actionID: String,
        connectionID: String = "",
        frameID: String = "",
        value: String = ""
    ) -> String {
        let dataSource = WebSocketDataSource.shared
        guard let connection = dataSource.getConnection(withId: connectionID) else {
            if actionID == "clear_all" {
                clearAllData()
                return "WebSocket connections and frames cleared."
            }
            return "This WebSocket connection is no longer available."
        }

        switch actionID {
        case "select_connection":
            dataSource.markConnectionAsRead(connectionID)
            return "Connection opened."
        case "close_connection":
            dataSource.forceCloseConnection(connectionID)
            return "Close requested for the WebSocket connection."
        case "clear_frames":
            dataSource.clearFrames(for: connectionID)
            return "Frames cleared for this connection."
        case "copy_url":
            UIPasteboard.general.string = connection.url.absoluteString
            return "WebSocket URL copied."
        case "copy_payload":
            guard let frame = connection.frames.first(where: { $0.id == frameID }) else {
                return "This WebSocket frame is no longer available."
            }
            UIPasteboard.general.string = frame.prettyPrintedJSON ?? frame.payloadString ?? frame.hexDump
            return "Frame payload copied."
        case "send_frame", "resend_frame":
            let message: URLSessionWebSocketTask.Message
            if actionID == "resend_frame" {
                guard let frame = connection.frames.first(where: { $0.id == frameID }) else {
                    return "Select a frame to resend first."
                }
                if frame.type == .binary {
                    message = .data(frame.payload)
                } else {
                    message = .string(frame.payloadString ?? frame.payload.base64EncodedString())
                }
            } else if value.lowercased().hasPrefix("base64:") {
                guard let payload = Data(base64Encoded: String(value.dropFirst("base64:".count))) else {
                    return "Enter valid text or base64:<data>."
                }
                message = .data(payload)
            } else {
                message = .string(value)
            }

            WebSocketMonitor.shared.sendMessage(message, onConnectionId: connectionID) { result in
                if case .failure(let error) = result {
                    Debug.print("[WebSocket Inspector] Unable to send frame: \(error.localizedDescription)")
                }
            }
            return "Frame send requested."
        case "export":
            let contents = WebSocketDataSource.shared.getConnectionsSortedByActivity().map { item in
                let frames = item.frames.sorted { $0.timestamp < $1.timestamp }.map { frame in
                    let payload = frame.prettyPrintedJSON ?? frame.payloadString ?? "<Binary Data: \(frame.payloadSize) bytes>\n\(frame.hexDump)"
                    return "\(sharedFrameDirection(frame.direction)) · \(sharedFrameType(frame.type)) · \(frame.timestamp)\n\(payload)"
                }.joined(separator: "\n\n")
                return "\(item.url.absoluteString)\nStatus: \(item.status.displayString)\nStarted: \(item.createdAt)\nLast activity: \(item.lastActivityAt)\n\n\(frames.isEmpty ? "No frames recorded." : frames)"
            }.joined(separator: "\n\n--------------------\n\n")
            FileSharingManager.generateFileAndShare(text: contents, fileName: "debugswift-websocket")
            return "Sharing WebSocket history."
        default:
            return "Unknown WebSocket action: \(actionID)."
        }
    }
}

private func sharedFrameDirection(_ direction: WebSocketFrameDirection) -> String {
    switch direction {
    case .sent: "Sent"
    case .received: "Received"
    }
}

private func sharedFrameType(_ type: WebSocketFrameType) -> String {
    switch type {
    case .text: "Text"
    case .binary: "Binary"
    case .ping: "Ping"
    case .pong: "Pong"
    case .close: "Close"
    case .continuation: "Continuation"
    }
}

private func sharedStatusDetail(_ status: WebSocketConnectionStatus) -> String {
    if case .error(let error) = status { return error.localizedDescription }
    return ""
}
