import SwiftUI

/// Frames that took longer than 32 ms to draw: how many, how slow, and when.
struct DebugFrameDropsView: View {
    @State var detail: DebugFrameDetail? = nil
    @State var failure = ""

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if let detail {
                Section("Summary") {
                    LabeledContent("Frames sampled") { Text(verbatim: "\(detail.frames)") }
                    LabeledContent("Slow frames (over 32 ms)") { Text(verbatim: "\(detail.slow)") }
                    LabeledContent("Share of slow frames") {
                        Text(verbatim: detail.frames > 0 ? String(format: "%.1f%%", Double(detail.slow) * 100 / Double(detail.frames)) : "0%")
                    }
                    LabeledContent("Slowest frame") { Text(verbatim: "\(detail.slowest) ms") }
                }
                Section("Recent slow frames (oldest to newest)") {
                    DebugSparkline(
                        values: detail.events.reversed().suffix(60).map { Double($0.ms) },
                        color: Color.orange,
                    )
                }
                Section("Timeline, newest first") {
                    if detail.events.isEmpty {
                        Text(verbatim: "No slow frames captured.")
                            .foregroundColor(Color.secondary)
                    }
                    ForEach(0..<detail.events.count, id: \.self) { index in
                        HStack {
                            Text(verbatim: detail.events[index].time)
                                .font(.system(.footnote, design: .monospaced))
                            Spacer()
                            Text(verbatim: "\(detail.events[index].ms) ms")
                                .foregroundColor(detail.events[index].ms > 100 ? Color.red : Color.orange)
                        }
                    }
                }
            }
            Section {
                Button("Refresh") { load() }
                Button("Clear", role: .destructive) {
                    _ = DebugSwiftAndroidRuntime.perform(featureID: "frame_drops", actionID: "clear")
                    load()
                }
            }
        }
        .navigationTitle("Frame Drops")
        .task {
            while !Task.isCancelled {
                load()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func load() {
        switch DebugPerformanceDetail.fetch("frames", as: DebugFrameDetail.self) {
        case let .success(value):
            detail = value
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}
