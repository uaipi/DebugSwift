import SwiftUI

/// Sends the low-memory callbacks to the app, to see how it reacts, and shows the system's memory state.
struct DebugMemoryWarningView: View {
    @State var detail: DebugMemoryDetail? = nil
    @State var failure = ""
    @State var status = ""

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            Section {
                Button("Simulate a memory warning") {
                    status = DebugSwiftAndroidRuntime.perform(featureID: "memory_warning", actionID: "simulate_memory_warning")
                    load()
                    // The callbacks run on the main thread a moment later, so read the count again.
                    Task {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        load()
                    }
                }
                if !status.isEmpty {
                    Text(verbatim: status).font(.caption)
                }
            }
            if let detail {
                Section("State") {
                    LabeledContent("Warnings simulated") { Text(verbatim: "\(detail.simulated)") }
                    LabeledContent("System memory free") {
                        Text(verbatim: "\(debugByteCount(detail.systemAvailable)) of \(debugByteCount(detail.systemTotal))")
                    }
                    LabeledContent("System low on memory") { Text(verbatim: detail.lowMemory ? "Yes" : "No") }
                }
            }
            Section {
                Text(verbatim: "The button calls onLowMemory and the critical trim callback on the app and the foreground Activity. Android does not let an app put the whole system under real memory pressure.")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }
        }
        .navigationTitle("Memory Warning")
        .onAppear { load() }
    }

    func load() {
        switch DebugPerformanceDetail.fetch("memory", as: DebugMemoryDetail.self) {
        case let .success(value):
            detail = value
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}
