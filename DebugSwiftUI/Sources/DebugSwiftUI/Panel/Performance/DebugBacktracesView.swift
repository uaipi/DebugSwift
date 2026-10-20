import SwiftUI

/// Call stacks saved on demand, for the main thread or for every thread.
struct DebugBacktracesView: View {
    @State var captures: [DebugStackEntry] = []
    @State var failure = ""
    @State var status = ""

    var body: some View {
        List {
            Section {
                Button("Capture the main thread") { capture(all: false) }
                Button("Capture all threads") { capture(all: true) }
                Button("Clear", role: .destructive) {
                    _ = DebugPerformanceDetail.act("app.perf.clearBacktraces")
                    load()
                }
                if !status.isEmpty {
                    Text(verbatim: status).font(.caption)
                }
            }
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            Section("Captures, newest first") {
                if captures.isEmpty {
                    Text(verbatim: "No backtraces captured yet.")
                        .foregroundColor(Color.secondary)
                }
                ForEach(0..<captures.count, id: \.self) { index in
                    NavigationLink {
                        DebugTextDetailView(title: "Backtrace", text: captures[index].title + "\n\n" + captures[index].stack)
                    } label: {
                        Text(verbatim: captures[index].title)
                    }
                }
            }
        }
        .navigationTitle("Backtraces")
        .onAppear { load() }
    }

    func capture(all: Bool) {
        status = DebugPerformanceDetail.act("app.perf.captureBacktrace", ["all": all ? "true" : "false"])
        load()
    }

    func load() {
        switch DebugPerformanceDetail.fetch("backtraces", as: DebugBacktraceDetail.self) {
        case let .success(value):
            captures = value.captures
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}
