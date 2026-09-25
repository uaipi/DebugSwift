import Foundation
import SwiftUI

#if os(Android)
import debug.swift.android.DebugSwiftNativeBridge
#endif

#if os(iOS)
import DebugSwift
#endif

struct DebugSwiftNetworkRequestSnapshot: Codable, Identifiable {
    let id: String
    let url: String
    let method: String
    let statusCode: String
    let timestamp: String
    let timestampMilliseconds: Int64
    let durationMilliseconds: Int
    let requestBytes: Int
    let responseBytes: Int
    let requestHeaders: [String: String]
    let responseHeaders: [String: String]
    let requestBody: String
    let responseBody: String
    let decryptedResponseBody: String
    let requestBodyBase64: String?
    let responseBodyBase64: String?
    let decryptedResponseBodyBase64: String?
    let mimeType: String
    let error: String
    let graphqlOperation: String
    let source: String
    let isSuccess: Bool

    var displayRequestBody: String {
        requestBody.isEmpty ? (requestBytes == 0 ? "No request body" : "Binary request body · \(requestBytes) bytes") : requestBody
    }

    var displayResponseBody: String {
        let body = decryptedResponseBody.isEmpty ? responseBody : decryptedResponseBody
        return body.isEmpty ? (responseBytes == 0 ? "No response body" : "Binary response body · \(responseBytes) bytes") : body
    }
}

private struct DebugSwiftNetworkFilterSettings: Equatable {
    var methods: Set<String> = []
    var statusRanges: Set<String> = []
    var contentTypes: Set<String> = []
    var minResponseSeconds = ""
    var maxResponseSeconds = ""
    var minSizeBytes = ""
    var maxSizeBytes = ""
    var showOnlyErrors = false
    var showOnlySuccessful = false
    var host = ""
    var timeRange = "Any Time"

    var isActive: Bool {
        !methods.isEmpty || !statusRanges.isEmpty || !contentTypes.isEmpty ||
            !minResponseSeconds.isEmpty || !maxResponseSeconds.isEmpty ||
            !minSizeBytes.isEmpty || !maxSizeBytes.isEmpty || showOnlyErrors ||
            showOnlySuccessful || !host.isEmpty || timeRange != "Any Time"
    }

    func matches(_ request: DebugSwiftNetworkRequestSnapshot) -> Bool {
        if !methods.isEmpty && !methods.contains(request.method.uppercased()) { return false }
        if !statusRanges.isEmpty {
            guard let status = Int(request.statusCode) else { return false }
            let matchesRange = statusRanges.contains { range in
                switch range {
                case "2xx Success": (200..<300).contains(status)
                case "3xx Redirection": (300..<400).contains(status)
                case "4xx Client Error": (400..<500).contains(status)
                case "5xx Server Error": (500..<600).contains(status)
                default: false
                }
            }
            if !matchesRange { return false }
        }
        if !contentTypes.isEmpty && !contentTypes.contains(where: { request.mimeType.lowercased().contains($0) }) { return false }
        if let minValue = Double(minResponseSeconds), Double(request.durationMilliseconds) / 1_000 < minValue { return false }
        if let maxValue = Double(maxResponseSeconds), Double(request.durationMilliseconds) / 1_000 > maxValue { return false }
        if let minValue = Int(minSizeBytes), request.responseBytes < minValue { return false }
        if let maxValue = Int(maxSizeBytes), request.responseBytes > maxValue { return false }
        if showOnlyErrors && request.isSuccess { return false }
        if showOnlySuccessful && !request.isSuccess { return false }
        if !host.isEmpty && !request.url.lowercased().contains(host.lowercased()) { return false }
        if timeRange != "Any Time" {
            let interval: Int64 = timeRange == "Last Hour" ? 3_600_000 : 86_400_000
            if request.timestampMilliseconds < Int64(Date().timeIntervalSince1970 * 1_000) - interval { return false }
        }
        return true
    }
}

private struct DebugSwiftNetworkInspectorSnapshot: Codable {
    let requests: [DebugSwiftNetworkRequestSnapshot]
}

private struct DebugSwiftNetworkDecryptionSettings: Codable {
    var isEnabled = false
    var patterns: [String] = []
}

struct DebugSwiftNetworkSessionSnapshot: Codable, Identifiable {
    let id: String
    let startedAtMilliseconds: Int64
    let endedAtMilliseconds: Int64?
    let requestCount: Int
    let isActive: Bool

    var title: String {
        let date = Date(timeIntervalSince1970: Double(startedAtMilliseconds) / 1_000)
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }

    var subtitle: String {
        let count = requestCount == 0 ? "No requests" : "\(requestCount) request\(requestCount == 1 ? "" : "s")"
        guard !isActive, let endedAtMilliseconds else { return isActive ? "\(count) · Active" : count }
        let seconds = max(0, Int((endedAtMilliseconds - startedAtMilliseconds) / 1_000))
        return "\(count) · \(String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60))"
    }
}

private struct DebugSwiftNetworkSessionHistorySnapshot: Codable {
    let sessions: [DebugSwiftNetworkSessionSnapshot]
    let retentionDays: Int
}

private struct DebugSwiftNetworkSessionRequestsSnapshot: Codable {
    let requests: [DebugSwiftNetworkRequestSnapshot]
}

struct DebugSwiftNetworkSessionHistoryView: View {
    @State private var sessions: [DebugSwiftNetworkSessionSnapshot] = []
    @State private var retentionDays = 7
    @State private var isLoading = false
    @State private var statusMessage = ""
    @State private var confirmsClearAll = false
    @State private var confirmsDelete = false
    @State private var sessionToDelete: DebugSwiftNetworkSessionSnapshot?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Refresh") { refresh() }
                Spacer()
                Button("Clear All", role: .destructive) { confirmsClearAll = true }
                    .disabled(sessions.isEmpty || isLoading)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            List {
                if sessions.isEmpty {
                    Text(isLoading ? "Loading saved sessions…" : "No session history available.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ForEach(sessions) { session in
                        NavigationLink {
                            DebugSwiftNetworkSessionRequestsView(session: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(session.title)
                                    .font(.headline)
                                Text(session.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .contextMenu {
                            Button("Delete Session", role: .destructive) {
                                sessionToDelete = session
                                confirmsDelete = true
                            }
                        }
                    }
                }

                Section {
                    Text("Session history only preserves the last \(retentionDays) day\(retentionDays == 1 ? "" : "s") of data.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle("Session History")
        .onAppear { refresh() }
        .alert("Clear All Sessions?", isPresented: $confirmsClearAll) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) { perform("clear_all") }
        } message: {
            Text("This removes all saved network sessions. This action cannot be undone.")
        }
        .alert("Delete Session?", isPresented: $confirmsDelete) {
            Button("Cancel", role: .cancel) { sessionToDelete = nil }
            Button("Delete", role: .destructive) {
                if let sessionToDelete { perform("delete_session", sessionID: sessionToDelete.id) }
                sessionToDelete = nil
            }
        } message: {
            Text("This removes the selected saved session and its requests.")
        }
    }

    private func refresh(statusOverride: String? = nil) {
        isLoading = true
        Task {
            let json = await DebugSwiftAndroidRuntime.networkSessionHistorySnapshotJSON()
            if let data = json.data(using: .utf8),
               let snapshot = try? JSONDecoder().decode(DebugSwiftNetworkSessionHistorySnapshot.self, from: data) {
                sessions = snapshot.sessions
                retentionDays = max(snapshot.retentionDays, 1)
                statusMessage = statusOverride ?? "\(sessions.count) saved session\(sessions.count == 1 ? "" : "s")"
            } else {
                sessions = []
                statusMessage = "Saved sessions could not be loaded."
            }
            isLoading = false
        }
    }

    private func perform(_ actionID: String, sessionID: String = "") {
        Task {
            let result = await DebugSwiftAndroidRuntime.performNetworkSessionHistoryAction(
                actionID: actionID,
                sessionID: sessionID
            )
            refresh(statusOverride: result)
        }
    }
}

private struct DebugSwiftNetworkSessionRequestsView: View {
    let session: DebugSwiftNetworkSessionSnapshot

    @State private var requests: [DebugSwiftNetworkRequestSnapshot] = []
    @State private var searchText = ""
    @State private var statusMessage = ""
    @State private var isLoading = false
    @State private var confirmsImport = false

    private var filteredRequests: [DebugSwiftNetworkRequestSnapshot] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return requests }
        return requests.filter {
            $0.url.lowercased().contains(query) ||
                $0.method.lowercased().contains(query) ||
                $0.statusCode.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Refresh") { refresh() }
                Spacer()
                Button("Import to Response Modifier") { confirmsImport = true }
                    .disabled(requests.isEmpty || isLoading)
            }
            .font(.caption)
            .padding(.horizontal)
            .padding(.vertical, 10)

            TextField("Search requests", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)

            if filteredRequests.isEmpty {
                Spacer()
                Text(isLoading ? "Loading requests…" : "No requests in this session.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else {
                List {
                    ForEach(filteredRequests) { request in
                        NavigationLink {
                            DebugSwiftNetworkRequestDetail(request: request, featureID: "network_history")
                        } label: {
                            DebugSwiftNetworkRequestRow(request: request)
                        }
                    }
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle(session.title)
        .onAppear { refresh() }
        .alert("Import Session to Response Modifier?", isPresented: $confirmsImport) {
            Button("Cancel", role: .cancel) {}
            Button("Import", role: .destructive) { importSession() }
        } message: {
            Text("This replaces all existing response rewrite rules with \(requests.count) rule(s) from this session. Long sessions can create many rules and may reduce network matching performance.")
        }
    }

    private func refresh() {
        isLoading = true
        Task {
            let json = await DebugSwiftAndroidRuntime.networkSessionRequestsSnapshotJSON(sessionID: session.id)
            if let data = json.data(using: .utf8),
               let snapshot = try? JSONDecoder().decode(DebugSwiftNetworkSessionRequestsSnapshot.self, from: data) {
                requests = snapshot.requests
                statusMessage = "\(requests.count) request\(requests.count == 1 ? "" : "s")"
            } else {
                requests = []
                statusMessage = "Session requests could not be loaded."
            }
            isLoading = false
        }
    }

    private func importSession() {
        Task {
            statusMessage = await DebugSwiftAndroidRuntime.performNetworkSessionHistoryAction(
                actionID: "import_session",
                sessionID: session.id
            )
        }
    }
}

struct DebugSwiftNetworkInspectorView: View {
    let featureID: String

    @State private var requests: [DebugSwiftNetworkRequestSnapshot] = []
    @State private var searchText = ""
    @State private var selectedSource: String
    @State private var statusMessage = ""
    @State private var confirmsClear = false
    @State private var showingFilters = false
    @State private var filterSettings = DebugSwiftNetworkFilterSettings()
    @State private var filterDraft = DebugSwiftNetworkFilterSettings()
    @State private var decryptionSettings = DebugSwiftNetworkDecryptionSettings()
    @State private var decryptionURLPattern = ""
    @State private var decryptionBase64Key = ""

    init(featureID: String) {
        self.featureID = featureID
        _selectedSource = State(initialValue: featureID == "webview_network" ? "webview" : "http")
    }

    private var filteredRequests: [DebugSwiftNetworkRequestSnapshot] {
        let sourceFiltered = requests.filter { request in
            switch featureID {
            case "http": request.source == selectedSource
            case "webview_network": request.source == "webview"
            case "graphql": !request.graphqlOperation.isEmpty
            default: true
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = query.lowercased()
        let advancedFiltered = sourceFiltered.filter { filterSettings.matches($0) }
        let matching = query.isEmpty ? advancedFiltered : advancedFiltered.filter { request in
            [request.url, request.method, request.statusCode, request.requestBody, request.responseBody, request.graphqlOperation]
                .contains { $0.lowercased().contains(normalizedQuery) }
        }
        return matching.sorted { $0.timestampMilliseconds > $1.timestampMilliseconds }
    }

    private var statsRequests: [DebugSwiftNetworkRequestSnapshot] {
        requests.filter { featureID == "http" ? $0.source == selectedSource : true }
    }

    private var averageDuration: Int {
        guard !statsRequests.isEmpty else { return 0 }
        return statsRequests.map(\.durationMilliseconds).reduce(0, +) / statsRequests.count
    }

    private var totalDuration: Int {
        statsRequests.map(\.durationMilliseconds).reduce(0, +)
    }

    var body: some View {
        VStack(spacing: 0) {
            actionBar

            if featureID == "network_encryption" {
                decryptionControls
            }

            if featureID == "http" {
                Picker("Traffic", selection: $selectedSource) {
                    Text("HTTP").tag("http")
                    Text("WebView").tag("webview")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            statistics

            TextField("Search URL, method, body, or status", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.vertical, 8)

            if filteredRequests.isEmpty {
                Spacer()
                Text(requests.isEmpty ? emptyStateMessage : "No requests match this search.")
                    .foregroundColor(Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else {
                List {
                    ForEach(filteredRequests) { request in
                        NavigationLink(destination: DebugSwiftNetworkRequestDetail(request: request, featureID: featureID)) {
                            DebugSwiftNetworkRequestRow(request: request)
                        }
                        .contextMenu {
                            Button("Copy URL") { perform("copy_url", requestID: request.id) }
                            Button("Copy cURL") { perform("copy_curl", requestID: request.id) }
                        }
                    }
                }
                .refreshable { refresh() }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(Color.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle(navigationTitle)
        .onAppear {
            refresh()
            if featureID == "network_encryption" { refreshDecryptionSettings() }
        }
        .alert("Clear request history?", isPresented: $confirmsClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { perform("clear") }
        } message: {
            Text("This removes the captured requests shown by this tool.")
        }
        .sheet(isPresented: $showingFilters) {
            DebugSwiftNetworkFilterSheet(filter: $filterDraft) {
                filterSettings = filterDraft
                showingFilters = false
            } onCancel: {
                showingFilters = false
            }
        }
    }

    private var actionBar: some View {
        HStack {
            Button("Refresh") { refresh() }
            Spacer()
            Button(filterSettings.isActive ? "Filters •" : "Filters") {
                filterDraft = filterSettings
                showingFilters = true
            }
            Button("Export HAR") { perform("export_har") }
                .disabled(filteredRequests.isEmpty)
            Button("Clear", role: .destructive) { confirmsClear = true }
                .disabled(filteredRequests.isEmpty)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var statistics: some View {
        HStack(spacing: 4) {
            DebugSwiftNetworkStat(title: "Total", value: "\(statsRequests.count)")
            DebugSwiftNetworkStat(title: "Success", value: "\(successRate)%")
            DebugSwiftNetworkStat(title: "Avg Time", value: Self.formatDuration(averageDuration))
            DebugSwiftNetworkStat(title: "Total Time", value: Self.formatDuration(totalDuration))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.12))
    }

    private var decryptionControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Decrypt matching responses", isOn: Binding(
                get: { decryptionSettings.isEnabled },
                set: { setDecryptionEnabled($0) }
            ))

            Text("AES-GCM keys are matched against request URLs using regular expressions. New captured responses use this setting.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("URL regular expression", text: $decryptionURLPattern)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Base64 AES key (16, 24, or 32 bytes)", text: $decryptionBase64Key)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            HStack {
                Button("Register key") { registerDecryptionKey() }
                    .disabled(decryptionURLPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || decryptionBase64Key.isEmpty)
                Spacer()
                Button("Clear keys", role: .destructive) { performDecryptionAction("clear_keys") }
                    .disabled(decryptionSettings.patterns.isEmpty)
            }

            if !decryptionSettings.patterns.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Registered URL patterns")
                        .font(.caption.bold())
                    ForEach(decryptionSettings.patterns, id: \.self) { pattern in
                        Text(pattern)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08))
    }

    private var successRate: Int {
        guard !statsRequests.isEmpty else { return 0 }
        return Int((Double(statsRequests.filter(\.isSuccess).count) / Double(statsRequests.count) * 100).rounded())
    }

    private var navigationTitle: String {
        switch featureID {
        case "graphql": "GraphQL"
        case "network_encryption": "Response Decryption"
        case "har_export": "HAR Export"
        case "webview_network": "WebView Network"
        default: "Network"
        }
    }

    private var emptyStateMessage: String {
        if featureID == "webview_network" || (featureID == "http" && selectedSource == "webview") {
            return "No WebView requests captured. Install DebugSwiftWebViewClient in the host app."
        }
        #if os(Android)
        return "No HTTP requests captured. On Android, add DebugSwiftOkHttpInterceptor to the host OkHttpClient.Builder."
        #else
        return "No HTTP requests captured."
        #endif
    }

    private func refresh() {
        let json = DebugSwiftAndroidRuntime.networkInspectorSnapshot(featureID: featureID)
        guard let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(DebugSwiftNetworkInspectorSnapshot.self, from: data) else {
            requests = []
            statusMessage = "Network data could not be loaded."
            return
        }
        requests = snapshot.requests
        statusMessage = requests.count == 1 ? "1 captured request" : "\(requests.count) captured requests"
    }

    private func perform(_ actionID: String, requestID: String = "") {
        statusMessage = DebugSwiftAndroidRuntime.performNetworkInspectorAction(
            featureID: featureID,
            actionID: actionID,
            requestID: requestID
        )
        refresh()
    }

    private func refreshDecryptionSettings() {
        let json = DebugSwiftAndroidRuntime.networkDecryptionSettings()
        guard let data = json.data(using: .utf8),
              let settings = try? JSONDecoder().decode(DebugSwiftNetworkDecryptionSettings.self, from: data) else {
            decryptionSettings = DebugSwiftNetworkDecryptionSettings()
            return
        }
        decryptionSettings = settings
    }

    private func setDecryptionEnabled(_ enabled: Bool) {
        performDecryptionAction("set_enabled", value: enabled ? "true" : "false")
    }

    private func registerDecryptionKey() {
        let pattern = decryptionURLPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = decryptionBase64Key.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = DebugSwiftAndroidRuntime.performNetworkDecryptionAction(
            actionID: "register_key",
            value: "\(pattern):\(key)"
        )
        statusMessage = message
        if message.hasPrefix("AES-GCM key registered") {
            decryptionURLPattern = ""
            decryptionBase64Key = ""
        }
        refreshDecryptionSettings()
        refresh()
        statusMessage = message
    }

    private func performDecryptionAction(_ actionID: String, value: String = "") {
        statusMessage = DebugSwiftAndroidRuntime.performNetworkDecryptionAction(actionID: actionID, value: value)
        refreshDecryptionSettings()
    }

    static func formatDuration(_ milliseconds: Int) -> String {
        if milliseconds < 1_000 { return "\(milliseconds)ms" }
        return String(format: "%.2fs", Double(milliseconds) / 1_000)
    }
}

private struct DebugSwiftNetworkFilterSheet: View {
    @Binding var filter: DebugSwiftNetworkFilterSettings
    let onApply: () -> Void
    let onCancel: () -> Void

    private let methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
    private let statuses = ["2xx Success", "3xx Redirection", "4xx Client Error", "5xx Server Error"]
    private let contentTypes = ["json", "xml", "html", "image", "text", "video", "audio", "pdf"]

    var body: some View {
        NavigationStack {
            Form {
                Section("HTTP methods") {
                    ForEach(methods, id: \.self) { method in
                        Toggle(method, isOn: selectionBinding(for: method, in: $filter.methods))
                    }
                }
                Section("Status codes") {
                    ForEach(statuses, id: \.self) { status in
                        Toggle(status, isOn: selectionBinding(for: status, in: $filter.statusRanges))
                    }
                }
                Section("Content types") {
                    ForEach(contentTypes, id: \.self) { type in
                        Toggle(type.uppercased(), isOn: selectionBinding(for: type, in: $filter.contentTypes))
                    }
                }
                Section("Response time (seconds)") {
                    TextField("Minimum", text: $filter.minResponseSeconds)
                    TextField("Maximum", text: $filter.maxResponseSeconds)
                }
                Section("Response size (bytes)") {
                    TextField("Minimum", text: $filter.minSizeBytes)
                    TextField("Maximum", text: $filter.maxSizeBytes)
                }
                Section("Results") {
                    Toggle("Show Only Errors", isOn: Binding(
                        get: { filter.showOnlyErrors },
                        set: { filter.showOnlyErrors = $0; if $0 { filter.showOnlySuccessful = false } }
                    ))
                    Toggle("Show Only Successful", isOn: Binding(
                        get: { filter.showOnlySuccessful },
                        set: { filter.showOnlySuccessful = $0; if $0 { filter.showOnlyErrors = false } }
                    ))
                }
                Section("Host") {
                    TextField("api.example.com", text: $filter.host)
                }
                Section("Time range") {
                    Picker("Requests from", selection: $filter.timeRange) {
                        Text("Any Time").tag("Any Time")
                        Text("Last Hour").tag("Last Hour")
                        Text("Last Day").tag("Last Day")
                    }
                }
                Section {
                    Button("Clear All Filters", role: .destructive) {
                        filter = DebugSwiftNetworkFilterSettings()
                    }
                }
            }
            .navigationTitle("Filter Requests")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", action: onApply)
                }
            }
        }
    }

    private func selectionBinding(for value: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(value) },
            set: { selected in
                var values = set.wrappedValue
                if selected { values.insert(value) }
                else { values.remove(value) }
                set.wrappedValue = values
            }
        )
    }
}

private struct DebugSwiftNetworkStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption2)
                .foregroundColor(Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DebugSwiftNetworkRequestRow: View {
    let request: DebugSwiftNetworkRequestSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(request.method)
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(Color.accentColor)
                Text(request.statusCode)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(statusColor)
                Spacer()
                Text(DebugSwiftNetworkInspectorView.formatDuration(request.durationMilliseconds))
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }
            Text(request.url)
                .font(.system(.footnote, design: .monospaced))
                .lineLimit(2)
            HStack {
                Text(request.timestamp)
                Spacer()
                Text("↓ \(request.responseBytes) bytes")
            }
            .font(.caption2)
            .foregroundColor(Color.secondary)
            if !request.error.isEmpty {
                Text(request.error)
                    .font(.caption)
                    .foregroundColor(Color.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 5)
    }

    private var statusColor: Color {
        guard let status = Int(request.statusCode) else { return .secondary }
        if (200..<300).contains(status) { return .green }
        if status >= 400 { return .red }
        return .orange
    }
}

private struct DebugSwiftNetworkRequestDetail: View {
    let request: DebugSwiftNetworkRequestSnapshot
    let featureID: String

    @State private var searchText = ""
    @State private var statusMessage = ""
    @State private var confirmsReplay = false

    private var detailSections: [(String, String)] {
        var sections: [(String, String)] = [
            ("Request Headers", formattedHeaders(request.requestHeaders)),
            ("Request Body", request.displayRequestBody),
            ("Response Headers", formattedHeaders(request.responseHeaders)),
            (request.decryptedResponseBody.isEmpty ? "Response Body" : "Decrypted Response Body", request.displayResponseBody)
        ]
        if !request.decryptedResponseBody.isEmpty && !request.responseBody.isEmpty {
            sections.append(("Raw Response Body", request.responseBody))
        }
        return sections
    }

    private var visibleSections: [(String, String)] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = query.lowercased()
        return query.isEmpty ? detailSections : detailSections.filter {
            $0.0.lowercased().contains(normalizedQuery) || $0.1.lowercased().contains(normalizedQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            TextField("Search request details", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)

            List {
                Section("General") {
                    DebugSwiftNetworkKeyValue(title: "Method", value: request.method)
                    DebugSwiftNetworkKeyValue(title: "URL", value: request.url)
                    DebugSwiftNetworkKeyValue(title: "Status", value: request.statusCode)
                    DebugSwiftNetworkKeyValue(title: "Started", value: request.timestamp)
                    DebugSwiftNetworkKeyValue(title: "Duration", value: DebugSwiftNetworkInspectorView.formatDuration(request.durationMilliseconds))
                    DebugSwiftNetworkKeyValue(title: "Request size", value: "\(request.requestBytes) bytes")
                    DebugSwiftNetworkKeyValue(title: "Response size", value: "\(request.responseBytes) bytes")
                    if !request.mimeType.isEmpty {
                        DebugSwiftNetworkKeyValue(title: "MIME type", value: request.mimeType)
                    }
                    if !request.error.isEmpty {
                        DebugSwiftNetworkKeyValue(title: "Error", value: request.error)
                    }
                }

                if !request.graphqlOperation.isEmpty {
                    Section("GraphQL") {
                        DebugSwiftNetworkKeyValue(title: "Operation", value: request.graphqlOperation)
                    }
                }

                ForEach(visibleSections, id: \.0) { section in
                    Section(section.0) {
                        Text(section.1)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        Button("Copy \(section.0)") { copy(section.1) }
                    }
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(Color.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle("Request Details")
        .alert("Replay this request?", isPresented: $confirmsReplay) {
            Button("Cancel", role: .cancel) {}
            Button("Replay") { perform("replay") }
        } message: {
            Text("\(request.method) \(request.url)")
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button("Copy Log") { perform("copy_log") }
            Button("Share") { perform("share_log") }
            Button("cURL") { perform("copy_curl") }
            Button("Replay") { confirmsReplay = true }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    private func perform(_ actionID: String) {
        if featureID == "network_history" {
            switch actionID {
            case "copy_log":
                copy(requestLogText)
            case "share_log":
                statusMessage = DebugSwiftAndroidRuntime.shareNetworkSessionRequestLog(requestLogText)
            case "copy_curl":
                copy(cURLCommand)
            case "replay":
                Task {
                    statusMessage = await DebugSwiftAndroidRuntime.replayNetworkSessionRequest(requestID: request.id)
                }
            default:
                statusMessage = "Unknown session request action: \(actionID)."
            }
            return
        }
        statusMessage = DebugSwiftAndroidRuntime.performNetworkInspectorAction(
            featureID: featureID,
            actionID: actionID,
            requestID: request.id
        )
    }

    private func copy(_ value: String) {
        statusMessage = DebugSwiftAndroidRuntime.performNetworkInspectorAction(
            featureID: featureID,
            actionID: "copy_text",
            requestID: request.id,
            text: value
        )
    }

    private func formattedHeaders(_ headers: [String: String]) -> String {
        headers.keys.sorted().map { "\($0): \(headers[$0] ?? "")" }.joined(separator: "\n").ifEmpty("No headers")
    }

    private var requestLogText: String {
        """
        [\(request.method)] \(request.timestamp) (\(request.statusCode))

        ------- URL -------
        \(request.url)

        ------- REQUEST HEADER -------
        \(formattedHeaders(request.requestHeaders))

        ------- REQUEST -------
        \(request.displayRequestBody)

        ------- RESPONSE HEADER -------
        \(formattedHeaders(request.responseHeaders))

        ------- RESPONSE -------
        \(request.displayResponseBody)

        ------- TOTAL TIME -------
        \(DebugSwiftNetworkInspectorView.formatDuration(request.durationMilliseconds))

        ------- MIME TYPE -------
        \(request.mimeType.isEmpty ? "No data" : request.mimeType)
        """
    }

    private var cURLCommand: String {
        var command = "curl -X \(shellQuote(request.method)) \(shellQuote(request.url))"
        for key in request.requestHeaders.keys.sorted() {
            let sensitive = ["authorization", "cookie", "set-cookie"].contains(key.lowercased())
            let value = sensitive ? "<redacted>" : request.requestHeaders[key] ?? ""
            command += " -H \(shellQuote("\(key): \(value)"))"
        }
        if !request.requestBody.isEmpty {
            command += " --data-raw \(shellQuote(request.requestBody))"
        }
        return command
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

private struct DebugSwiftNetworkKeyValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundColor(Color.secondary)
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

extension DebugSwiftAndroidRuntime {
    @MainActor
    static func networkSessionHistorySnapshotJSON() async -> String {
        #if os(Android)
        return DebugSwiftNativeBridge.networkSessionHistorySnapshotJSON()
        #elseif os(iOS)
        if #available(iOS 17.0, *) {
            return await DebugSwift.Network.shared.sharedSessionHistorySnapshotJSON()
        }
        return "{\"sessions\":[],\"retentionDays\":7}"
        #else
        return "{\"sessions\":[],\"retentionDays\":7}"
        #endif
    }

    @MainActor
    static func networkSessionRequestsSnapshotJSON(sessionID: String) async -> String {
        #if os(Android)
        return DebugSwiftNativeBridge.networkSessionRequestsSnapshotJSON(sessionID)
        #elseif os(iOS)
        if #available(iOS 17.0, *) {
            return await DebugSwift.Network.shared.sharedSessionRequestsSnapshotJSON(sessionID: sessionID)
        }
        return "{\"requests\":[]}"
        #else
        return "{\"requests\":[]}"
        #endif
    }

    @MainActor
    static func performNetworkSessionHistoryAction(actionID: String, sessionID: String) async -> String {
        #if os(Android)
        return DebugSwiftNativeBridge.performNetworkSessionHistoryAction(actionID, sessionID)
        #elseif os(iOS)
        if #available(iOS 17.0, *) {
            return await DebugSwift.Network.shared.performSharedSessionHistoryAction(actionID: actionID, sessionID: sessionID)
        }
        return "Session history requires iOS 17 or newer."
        #else
        return "Session history is unavailable."
        #endif
    }

    @MainActor
    static func shareNetworkSessionRequestLog(_ text: String) -> String {
        #if os(Android)
        return DebugSwiftNativeBridge.shareNetworkSessionRequestLog(text)
        #elseif os(iOS)
        if #available(iOS 17.0, *) {
            return DebugSwift.Network.shared.shareSharedSessionRequestLog(text)
        }
        return "Session history requires iOS 17 or newer."
        #else
        return "Session history sharing is unavailable."
        #endif
    }

    @MainActor
    static func replayNetworkSessionRequest(requestID: String) async -> String {
        #if os(Android)
        return DebugSwiftNativeBridge.replayNetworkSessionRequest(requestID)
        #elseif os(iOS)
        if #available(iOS 17.0, *) {
            return await DebugSwift.Network.shared.replaySharedSessionRequest(id: requestID)
        }
        return "Session history requires iOS 17 or newer."
        #else
        return "Session history replay is unavailable."
        #endif
    }

    @MainActor
    static func networkDecryptionSettings() -> String {
        #if os(Android)
        return DebugSwiftNativeBridge.networkDecryptionSettingsJSON()
        #elseif os(iOS)
        return DebugSwift.Network.shared.sharedDecryptionSettingsJSON()
        #else
        return "{\"isEnabled\":false,\"patterns\":[]}"
        #endif
    }

    @MainActor
    static func performNetworkDecryptionAction(actionID: String, value: String = "") -> String {
        #if os(Android)
        return DebugSwiftNativeBridge.performNetworkDecryptionAction(actionID, value)
        #elseif os(iOS)
        return DebugSwift.Network.shared.performSharedDecryptionAction(actionID: actionID, value: value)
        #else
        return "Response decryption is unavailable."
        #endif
    }

    @MainActor
    static func networkInspectorSnapshot(featureID: String) -> String {
        #if os(Android)
        return DebugSwiftNativeBridge.networkInspectorSnapshot(featureID)
        #elseif os(iOS)
        prepareIOSDebugger()
        return DebugSwift.Network.shared.sharedInspectorSnapshotJSON(featureID: featureID)
        #else
        return "{\"requests\":[]}"
        #endif
    }

    @MainActor
    static func performNetworkInspectorAction(
        featureID: String,
        actionID: String,
        requestID: String,
        text: String? = nil
    ) -> String {
        #if os(Android)
        if actionID == "copy_text", let text {
            return DebugSwiftNativeBridge.networkInspectorAction(featureID, "copy_text", text)
        }
        return DebugSwiftNativeBridge.networkInspectorAction(featureID, actionID, requestID)
        #elseif os(iOS)
        prepareIOSDebugger()
        if actionID == "copy_text", let text {
            UIPasteboard.general.string = text
            return "Copied to clipboard."
        }
        return DebugSwift.Network.shared.performSharedInspectorAction(
            featureID: featureID,
            actionID: actionID,
            requestID: requestID
        )
        #else
        return "Network action is unavailable."
        #endif
    }
}
