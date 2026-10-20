import SwiftUI

struct DebugAgentEntry: Decodable {
    let time: Double
    let kind: String
    let location: String
    let message: String
}

struct DebugAgentLogState: Decodable {
    let enabled: Bool
    let session: String
    let path: String
    let size: Int
    let entries: [DebugAgentEntry]
}

/// Streams the app's events, network calls, console messages and crashes into an NDJSON file that a
/// coding agent or a script can read. This screen turns capture on, shows the newest entries and
/// shares the file.
struct DebugAgentLogView: View {
    @State var state: DebugAgentLogState? = nil
    @State var failure = ""
    @State var status = ""

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if let state {
                Section {
                    Toggle("Capture", isOn: Binding(
                        get: { state.enabled },
                        set: { on in set(on, current: state.enabled) },
                    ))
                    LabeledContent("File size") { Text(verbatim: debugByteCount(state.size)) }
                    Text(verbatim: state.path)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(Color.secondary)
                }
                Section {
                    Button("Share the log file") {
                        status = DebugSwiftAndroidRuntime.perform(featureID: "agent_debug_log", actionID: "export")
                    }
                    Button("Clear the log", role: .destructive) {
                        status = DebugSwiftAndroidRuntime.perform(featureID: "agent_debug_log", actionID: "clear")
                        load()
                    }
                    if !status.isEmpty {
                        Text(verbatim: status).font(.caption)
                    }
                }
                Section("Newest entries (\(state.entries.count))") {
                    if state.entries.isEmpty {
                        Text(verbatim: state.enabled ? "Nothing captured yet." : "Turn capture on to collect entries.")
                            .foregroundColor(Color.secondary)
                    }
                    ForEach(0..<state.entries.count, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "\(state.entries[index].kind) · \(state.entries[index].location)")
                                .font(.caption)
                                .foregroundColor(Color.secondary)
                            Text(verbatim: state.entries[index].message)
                                .font(.system(.footnote, design: .monospaced))
                                .lineLimit(3)
                        }
                    }
                }
            }
        }
        .navigationTitle("Agent Debug Log")
        .task {
            while !Task.isCancelled {
                load()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func set(_ on: Bool, current: Bool) {
        guard on != current else { return }
        status = DebugSwiftAndroidRuntime.perform(featureID: "agent_debug_log", actionID: "toggle")
        load()
    }

    func load() {
        switch DebugResourceClient.fetch("app.agentlog.state", as: DebugAgentLogState.self) {
        case let .success(value):
            state = value
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}
