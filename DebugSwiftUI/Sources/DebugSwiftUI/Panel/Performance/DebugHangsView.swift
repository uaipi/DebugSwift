import SwiftUI

/// Moments the main thread did not respond, with the stack it was stuck in, and Android's own ANR reports.
struct DebugHangsView: View {
    @State var detail: DebugHangDetail? = nil
    @State var anrs: [DebugCrashExit] = []
    @State var failure = ""
    @State var status = ""

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if let detail {
                Section("Main thread stalls (over \(detail.thresholdMs) ms)") {
                    if detail.stalls.isEmpty {
                        Text(verbatim: "No stalls detected.")
                            .foregroundColor(Color.secondary)
                    }
                    ForEach(0..<detail.stalls.count, id: \.self) { index in
                        NavigationLink {
                            DebugTextDetailView(
                                title: "\(detail.stalls[index].ms) ms stall",
                                text: detail.stalls[index].time + "\n\n" + detail.stalls[index].stack,
                            )
                        } label: {
                            HStack {
                                Text(verbatim: detail.stalls[index].time)
                                    .font(.system(.footnote, design: .monospaced))
                                Spacer()
                                Text(verbatim: "\(detail.stalls[index].ms) ms")
                                    .foregroundColor(Color.red)
                            }
                        }
                    }
                }
            }
            Section("Android ANR reports") {
                if anrs.isEmpty {
                    Text(verbatim: "Android has not reported an ANR for this app.")
                        .foregroundColor(Color.secondary)
                }
                ForEach(anrs) { exit in
                    NavigationLink {
                        DebugTextDetailView(title: "ANR", text: debugDateText(exit.date) + "\n" + exit.description + "\n\n" + exit.trace)
                    } label: {
                        DebugCrashExitRow(exit: exit)
                    }
                }
            }
            Section("Try it") {
                Button("Block the main thread for 1 second") {
                    status = DebugPerformanceDetail.act("app.perf.stall", ["ms": "1000"])
                }
                Button("Refresh") { load() }
                Button("Clear", role: .destructive) {
                    _ = DebugSwiftAndroidRuntime.perform(featureID: "hangs", actionID: "clear")
                    load()
                }
                if !status.isEmpty {
                    Text(verbatim: status).font(.caption)
                }
            }
        }
        .navigationTitle("Hangs and ANRs")
        .task {
            while !Task.isCancelled {
                load()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func load() {
        switch DebugPerformanceDetail.fetch("hangs", as: DebugHangDetail.self) {
        case let .success(value):
            detail = value
            failure = ""
        case let .failure(error):
            failure = error.message
        }
        if case let .success(crashes) = DebugResourceClient.fetch("app.crashes", as: DebugCrashListing.self) {
            anrs = crashes.exits.filter { $0.reason == "ANR" }
        }
    }
}
