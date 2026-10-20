import SwiftUI

struct DebugComposeState: Decodable {
    let total: Int
    let recomposers: Int
    let perSecond: [Int]
    let probeRenders: Int
    let frames: Int
}

/// How often Compose recomposes, sampled once a second while this screen is open. High, steady rates
/// on a still screen point at state that changes more than it should.
struct DebugComposeRendersView: View {
    @State var state: DebugComposeState? = nil
    @State var failure = ""

    var rates: [Double] {
        (state?.perSecond ?? []).map { Double($0) }
    }

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if let state {
                Section {
                    DebugMetricCard(
                        title: "Recompositions per second",
                        value: "\(state.perSecond.last ?? 0)",
                        history: history,
                        color: Color.purple,
                    )
                }
                Section("Totals") {
                    LabeledContent("Recompositions since start") { Text(verbatim: "\(state.total)") }
                    LabeledContent("Busiest second") { Text(verbatim: "\(state.perSecond.max() ?? 0)") }
                    LabeledContent("Average, last minute") {
                        Text(verbatim: String(format: "%.1f", rates.isEmpty ? 0 : rates.reduce(0, +) / Double(rates.count)))
                    }
                    LabeledContent("Compose roots running") { Text(verbatim: "\(state.recomposers)") }
                    LabeledContent("Frames drawn") { Text(verbatim: "\(state.frames)") }
                    if state.probeRenders > 0 {
                        LabeledContent("Counted by a DebugSwiftComposeProbe") { Text(verbatim: "\(state.probeRenders)") }
                    }
                }
                Section {
                    Text(verbatim: "Counts every change Compose applies in this app, with no wrapper in your UI. Wrap a screen in DebugSwiftComposeProbe to count renders of just that screen.")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
            }
        }
        .navigationTitle("Compose Render Tracking")
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    var history: DebugMetricHistory {
        var result = DebugMetricHistory()
        for value in rates { result.append(value) }
        return result
    }

    func refresh() {
        switch DebugResourceClient.fetch("app.compose.state", as: DebugComposeState.self) {
        case let .success(value):
            state = value
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}
