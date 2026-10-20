import SwiftUI

/// Battery level and charging state, with the level over the time the screen has been open.
struct DebugBatteryView: View {
    @State var sample: DebugPerformanceSample? = nil
    @State var level = DebugMetricHistory()
    @State var failure = ""

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if let sample {
                Section {
                    DebugMetricCard(
                        title: "Level",
                        value: sample.batteryPercent >= 0 ? "\(sample.batteryPercent)%" : "Unknown",
                        history: level,
                        ceiling: 100,
                        color: sample.batteryPercent < 20 ? Color.red : Color.green,
                    )
                }
                Section("State") {
                    LabeledContent("Charging") { Text(verbatim: sample.charging ? "Yes" : "No") }
                    LabeledContent("Power source") { Text(verbatim: sample.plugged) }
                }
            }
        }
        .navigationTitle("Battery")
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func refresh() {
        switch DebugPerformanceSample.read() {
        case let .success(value):
            sample = value
            failure = ""
            if value.batteryPercent >= 0 { level.append(Double(value.batteryPercent)) }
        case let .failure(error):
            failure = error.message
        }
    }
}
