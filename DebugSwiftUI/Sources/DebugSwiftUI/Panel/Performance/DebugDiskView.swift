import SwiftUI

/// Storage the app uses and how much it reads and writes, as a rate while the screen is open.
struct DebugDiskView: View {
    @State var sample: DebugPerformanceSample? = nil
    @State var reads = DebugMetricHistory()
    @State var writes = DebugMetricHistory()
    @State var previous: DebugPerformanceSample? = nil
    @State var failure = ""

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if let sample {
                Section("Throughput (per second)") {
                    DebugMetricCard(
                        title: "Read",
                        value: debugByteCount(Int(reads.values.last ?? 0)) + "/s",
                        history: reads,
                        color: Color.blue,
                    )
                    DebugMetricCard(
                        title: "Write",
                        value: debugByteCount(Int(writes.values.last ?? 0)) + "/s",
                        history: writes,
                        color: Color.orange,
                    )
                }
                Section("Totals since the process started") {
                    LabeledContent("Read") { Text(verbatim: debugByteCount(sample.readBytes)) }
                    LabeledContent("Written") { Text(verbatim: debugByteCount(sample.writeBytes)) }
                }
                Section("App storage") {
                    LabeledContent("Files") { Text(verbatim: "\(sample.appFileCount)") }
                    LabeledContent("Size") { Text(verbatim: debugByteCount(sample.appFileBytes)) }
                    NavigationLink {
                        DebugFilesView(path: "")
                    } label: {
                        Text(verbatim: "Browse files")
                    }
                }
            }
        }
        .navigationTitle("Disk I/O")
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
            if let previous {
                reads.append(Double(max(0, value.readBytes - previous.readBytes)))
                writes.append(Double(max(0, value.writeBytes - previous.writeBytes)))
            }
            previous = value
            sample = value
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}
