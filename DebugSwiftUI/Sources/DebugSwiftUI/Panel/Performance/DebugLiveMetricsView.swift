import SwiftUI

/// CPU, memory and frame rate, sampled once a second while the screen is open.
struct DebugLiveMetricsView: View {
    @State var sample: DebugPerformanceSample? = nil
    @State var cpu = DebugMetricHistory()
    @State var memory = DebugMetricHistory()
    @State var frames = DebugMetricHistory()
    @State var failure = ""

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if let sample {
                Section {
                    DebugMetricCard(
                        title: "CPU",
                        value: String(format: "%.1f%%", sample.cpuPercent),
                        history: cpu,
                        ceiling: 100,
                        color: Color.orange,
                    )
                    DebugMetricCard(
                        title: "Memory (app heap)",
                        value: debugByteCount(sample.usedMemory),
                        history: memory,
                        ceiling: Double(sample.maxMemory),
                        color: Color.blue,
                    )
                    DebugMetricCard(
                        title: "Frames per second",
                        value: "\(sample.fps)",
                        history: frames,
                        ceiling: 120,
                        color: Color.green,
                    )
                }
                Section("Details") {
                    LabeledContent("Heap limit") { Text(verbatim: debugByteCount(sample.maxMemory)) }
                    LabeledContent("Native heap") { Text(verbatim: debugByteCount(sample.nativeHeap)) }
                    LabeledContent("System memory free") {
                        Text(verbatim: "\(debugByteCount(sample.systemAvailable)) of \(debugByteCount(sample.systemTotal))")
                    }
                    LabeledContent("Low memory") { Text(verbatim: sample.lowMemory ? "Yes" : "No") }
                    LabeledContent("Frames sampled") { Text(verbatim: "\(sample.frames)") }
                    LabeledContent("Slow frames (over 32 ms)") { Text(verbatim: "\(sample.slowFrames)") }
                    LabeledContent("Slowest frame") { Text(verbatim: "\(sample.slowestFrameMs) ms") }
                }
            }
        }
        .navigationTitle("Live Metrics")
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func refresh() {
        switch DebugPerformanceSample.read() {
        case let .success(value):
            sample = value
            failure = ""
            cpu.append(value.cpuPercent)
            memory.append(Double(value.usedMemory))
            frames.append(Double(value.fps))
        case let .failure(error):
            failure = error.message
        }
    }
}
