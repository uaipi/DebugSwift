import SwiftUI

/// Activities that were destroyed but are still reachable after five seconds, a sign of a leak.
struct DebugLeaksView: View {
    @State var detail: DebugLeakDetail? = nil
    @State var failure = ""
    @State var status = ""

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if let detail {
                Section("Summary") {
                    LabeledContent("Activities destroyed") { Text(verbatim: "\(detail.destroyed)") }
                    LabeledContent("Still held after 5 s") { Text(verbatim: "\(detail.candidates.count)") }
                }
                Section("Retained Activities") {
                    if detail.candidates.isEmpty {
                        Text(verbatim: "No retained Activity candidates detected.")
                            .foregroundColor(Color.secondary)
                    }
                    ForEach(0..<detail.candidates.count, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: detail.candidates[index].className)
                                .font(.system(.footnote, design: .monospaced))
                            Text(verbatim: "destroyed \(detail.candidates[index].ageSeconds) s ago")
                                .font(.caption)
                                .foregroundColor(Color.secondary)
                        }
                    }
                }
            }
            Section {
                Button("Collect garbage and recheck") {
                    status = DebugPerformanceDetail.act("app.perf.gc")
                    load()
                }
                Button("Refresh") { load() }
                if !status.isEmpty {
                    Text(verbatim: status).font(.caption)
                }
                Text(verbatim: "This is a reachability check. Confirm a leak with the Android Studio Memory Profiler.")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }
        }
        .navigationTitle("Leak Detection")
        .onAppear { load() }
    }

    func load() {
        switch DebugPerformanceDetail.fetch("leaks", as: DebugLeakDetail.self) {
        case let .success(value):
            detail = value
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}
