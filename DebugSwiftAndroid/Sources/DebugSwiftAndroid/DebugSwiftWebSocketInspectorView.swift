import Foundation
import SwiftUI

#if os(Android)
import debug.swift.android.DebugSwiftNativeBridge
#endif

#if os(iOS)
import DebugSwift
#endif

private struct DebugSwiftWebSocketInspectorSnapshot: Codable {
    let connections: [DebugSwiftWebSocketConnection]
    let frames: [DebugSwiftWebSocketFrame]
}

private struct DebugSwiftWebSocketConnection: Codable, Identifiable {
    let id: String
    let url: String
    let name: String
    let status: String
    let statusDetail: String
    let createdAtMilliseconds: Int64
    let lastActivityAtMilliseconds: Int64
    let frameCount: Int
    let sentCount: Int
    let receivedCount: Int
    let unreadFrameCount: Int
}

private struct DebugSwiftWebSocketFrame: Codable, Identifiable {
    let id: String
    let connectionID: String
    let timestampMilliseconds: Int64
    let direction: String
    let type: String
    let size: Int
    let payload: String
    let prettyPayload: String
    let payloadBase64: String
    let hexDump: String
    let hexTruncated: Bool

    var preview: String {
        let text = prettyPayload.isEmpty ? payload : prettyPayload
        return text.isEmpty ? "Binary data · \(size) bytes" : String(text.prefix(120))
    }
}

struct DebugSwiftWebSocketInspectorView: View {
    @State private var snapshot = DebugSwiftWebSocketInspectorSnapshot(connections: [], frames: [])
    @State private var selectedConnectionID = ""
    @State private var selectedFrameID = ""
    @State private var searchText = ""
    @State private var sendText = ""
    @State private var direction = "All"
    @State private var statusMessage = ""
    @State private var confirmation = ""
    @State private var refreshTimer: Timer?

    private var selectedConnection: DebugSwiftWebSocketConnection? {
        snapshot.connections.first { $0.id == selectedConnectionID }
    }

    private var selectedFrame: DebugSwiftWebSocketFrame? {
        snapshot.frames.first { $0.id == selectedFrameID }
    }

    private var visibleFrames: [DebugSwiftWebSocketFrame] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return snapshot.frames.filter { frame in
            (direction == "All" || frame.direction == direction) &&
                (query.isEmpty || frame.preview.lowercased().contains(query) || frame.hexDump.lowercased().contains(query))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            actionBar

            TextField("Search connections or frame payloads", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.vertical, 8)

            if !selectedConnectionID.isEmpty, let connection = selectedConnection {
                connectionContent(connection)
            } else {
                connectionList
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(Color.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle("WebSocket Inspector")
        .onAppear {
            refresh()
            refreshTimer?.invalidate()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in refresh() }
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
        .alert(confirmationTitle, isPresented: Binding(
            get: { !confirmation.isEmpty },
            set: { if !$0 { confirmation = "" } }
        )) {
            Button("Cancel", role: .cancel) {}
            Button(confirmation == "all" ? "Clear All" : "Clear Frames", role: .destructive) {
                if confirmation == "all" { clearAll() }
                else { clearFrames() }
                confirmation = ""
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 14) {
            Button("Refresh") { refresh() }
            Spacer()
            if selectedConnection != nil {
                Button("Copy URL") { statusMessage = perform("copy_url") }
                Button("Export") { statusMessage = perform("export") }
            } else {
                Button("Export") { statusMessage = perform("export") }
                Button("Clear", role: .destructive) { confirmation = "all" }
                    .disabled(snapshot.connections.isEmpty)
            }
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var connectionList: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let connections = snapshot.connections.filter { connection in
            query.isEmpty || connection.url.lowercased().contains(query) || connection.status.lowercased().contains(query)
        }

        return Group {
            if connections.isEmpty {
                Spacer()
                Text(snapshot.connections.isEmpty
                    ? emptyConnectionMessage
                    : "No WebSocket connections match this search.")
                    .foregroundColor(Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else {
                List {
                    Section("\(connections.count) connections · \(snapshot.connections.filter { ["Connecting", "Connected", "Reconnecting", "Closing"].contains($0.status) }.count) active") {
                        ForEach(connections) { connection in
                            Button {
                                selectedConnectionID = connection.id
                                selectedFrameID = ""
                                direction = "All"
                                statusMessage = perform("select_connection", connectionID: connection.id)
                                refresh()
                            } label: {
                                connectionRow(connection)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .refreshable { refresh() }
            }
        }
    }

    private func connectionContent(_ connection: DebugSwiftWebSocketConnection) -> some View {
        return List {
            Section("Connection") {
                keyValue("URL", connection.url)
                keyValue("Status", connection.status + (connection.statusDetail.isEmpty ? "" : " · \(connection.statusDetail)"))
                keyValue("Started", formattedDate(connection.createdAtMilliseconds))
                keyValue("Last activity", formattedDate(connection.lastActivityAtMilliseconds))
                keyValue("Frames", "\(connection.frameCount) · Sent \(connection.sentCount) · Received \(connection.receivedCount) · Unread \(connection.unreadFrameCount)")
                HStack {
                    Button("Back to Connections") {
                        selectedConnectionID = ""
                        selectedFrameID = ""
                        refresh()
                    }
                    Spacer()
                    Button("Close", role: .destructive) {
                        statusMessage = perform("close_connection")
                        refresh()
                    }
                    .disabled(connection.status == "Closed" || connection.status == "Error")
                    Button("Clear Frames", role: .destructive) { confirmation = "frames" }
                }
            }

            Section {
                Picker("Direction", selection: $direction) {
                    Text("All").tag("All")
                    Text("Sent").tag("Sent")
                    Text("Received").tag("Received")
                }
                .pickerStyle(.segmented)
            }

            Section("Frames · Newest first") {
                if visibleFrames.isEmpty {
                    Text("No matching frames. Send a text message or use base64:<data> for binary.")
                        .foregroundColor(Color.secondary)
                } else {
                    ForEach(visibleFrames) { frame in
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                selectedFrameID = frame.id
                            } label: {
                                frameRow(frame)
                            }
                            .buttonStyle(.plain)
                            if selectedFrameID == frame.id {
                                frameDetails(frame)
                            }
                        }
                    }
                }
            }

            Section("Send a frame") {
                TextField("Message or base64:<data>", text: $sendText)
                Button("Send") {
                    statusMessage = perform("send_frame", value: sendText)
                    sendText = ""
                    refresh()
                }
                .disabled(sendText.isEmpty || connection.status == "Closed" || connection.status == "Error")
                if let frame = selectedFrame {
                    Button("Resend selected frame") {
                        statusMessage = perform("resend_frame", frameID: frame.id)
                        refresh()
                    }
                    Button("Copy selected payload") {
                        statusMessage = perform("copy_payload", frameID: frame.id)
                    }
                }
            }
        }
        .refreshable { refresh() }
    }

    private func connectionRow(_ connection: DebugSwiftWebSocketConnection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(connection.name.isEmpty ? connection.url : connection.name)
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .lineLimit(2)
            HStack {
                Text(connection.status)
                Text("· \(connection.frameCount) frames")
                if connection.unreadFrameCount > 0 { Text("· \(connection.unreadFrameCount) unread") }
                Spacer()
            }
            .font(.caption)
            .foregroundColor(Color.secondary)
            HStack {
                Text("Sent \(connection.sentCount)")
                Text("Received \(connection.receivedCount)")
                Spacer()
                Text(formattedDate(connection.lastActivityAtMilliseconds))
            }
            .font(.caption2)
            .foregroundColor(Color.secondary)
        }
        .padding(.vertical, 5)
    }

    private func frameRow(_ frame: DebugSwiftWebSocketFrame) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(frame.direction.uppercased())
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(frame.direction == "Sent" ? Color.accentColor : Color.green)
                Text(frame.type)
                    .font(.caption)
                    .foregroundColor(Color.secondary)
                Spacer()
                Text("\(frame.size) bytes")
                    .font(.caption2)
                    .foregroundColor(Color.secondary)
            }
            Text(frame.preview)
                .font(.system(.footnote, design: .monospaced))
                .lineLimit(3)
            Text(formattedDate(frame.timestampMilliseconds))
                .font(.caption2)
                .foregroundColor(Color.secondary)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func frameDetails(_ frame: DebugSwiftWebSocketFrame) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            keyValue("Direction", frame.direction)
            keyValue("Type", frame.type)
            keyValue("Timestamp", formattedDate(frame.timestampMilliseconds))
            keyValue("Size", "\(frame.size) bytes")
            Text("Decoded payload")
                .font(.caption.weight(.semibold))
            Text(frame.prettyPayload.isEmpty ? "<Binary data>" : frame.prettyPayload)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            if !frame.payload.isEmpty {
                Text("Raw payload")
                    .font(.caption.weight(.semibold))
                Text(frame.payload)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Hex")
                .font(.caption.weight(.semibold))
            Text(frame.hexDump.isEmpty ? "(empty)" : frame.hexDump + (frame.hexTruncated ? "\n… payload preview truncated …" : ""))
                .font(.system(.caption2, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            if frame.payload.isEmpty && frame.size > 0 {
                Text("Base64 payload")
                    .font(.caption.weight(.semibold))
                Text(frame.payloadBase64)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Copy Payload") { statusMessage = perform("copy_payload", frameID: frame.id) }
                Button("Resend") { statusMessage = perform("resend_frame", frameID: frame.id); refresh() }
            }
        }
        .padding(.vertical, 6)
    }

    private func keyValue(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundColor(Color.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .multilineTextAlignment(.trailing)
        }
    }

    private func refresh() {
        let json = DebugSwiftAndroidRuntime.webSocketInspectorSnapshot(
            connectionID: selectedConnectionID,
            query: "",
            direction: ""
        )
        guard let data = json.data(using: .utf8),
              let loaded = try? JSONDecoder().decode(DebugSwiftWebSocketInspectorSnapshot.self, from: data) else {
            snapshot = DebugSwiftWebSocketInspectorSnapshot(connections: [], frames: [])
            statusMessage = "WebSocket data could not be loaded."
            return
        }
        snapshot = loaded
        if !selectedConnectionID.isEmpty && selectedConnection == nil {
            selectedConnectionID = ""
            selectedFrameID = ""
        }
    }

    private func clearAll() {
        statusMessage = perform("clear_all")
        selectedConnectionID = ""
        selectedFrameID = ""
        refresh()
    }

    private func clearFrames() {
        statusMessage = perform("clear_frames")
        selectedFrameID = ""
        refresh()
    }

    private var confirmationTitle: String {
        confirmation == "all" ? "Clear all WebSocket history?" : "Clear frames for this connection?"
    }

    private var confirmationMessage: String {
        confirmation == "all"
            ? "This removes every captured WebSocket connection and frame."
            : "The connection stays in the list, with its captured frames removed."
    }

    @MainActor
    private func perform(
        _ actionID: String,
        connectionID: String? = nil,
        frameID: String = "",
        value: String = ""
    ) -> String {
        #if os(Android)
        return DebugSwiftNativeBridge.performWebSocketInspectorAction(
            actionID,
            connectionID ?? selectedConnectionID,
            frameID,
            value
        )
        #elseif os(iOS)
        return DebugSwift.WebSocket.performSharedInspectorAction(
            actionID: actionID,
            connectionID: connectionID ?? selectedConnectionID,
            frameID: frameID,
            value: value
        )
        #else
        return "WebSocket actions are unavailable."
        #endif
    }

    private func formattedDate(_ milliseconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }

    private var emptyConnectionMessage: String {
        #if os(Android)
        return "No WebSocket connections captured. Add DebugSwiftWebSocketListener to the host OkHttp client."
        #else
        return "No WebSocket connections captured. Check that WebSocket monitoring is enabled in the host app."
        #endif
    }
}

private extension DebugSwiftAndroidRuntime {
    @MainActor
    static func webSocketInspectorSnapshot(connectionID: String, query: String, direction: String) -> String {
        #if os(Android)
        return DebugSwiftNativeBridge.webSocketInspectorSnapshot(connectionID, query, direction)
        #elseif os(iOS)
        DebugSwiftAndroidRuntime.prepareIOSDebugger()
        return DebugSwift.WebSocket.sharedInspectorSnapshotJSON(
            connectionID: connectionID,
            query: query,
            direction: direction
        )
        #else
        return "{\"connections\":[],\"frames\":[]}"
        #endif
    }
}
