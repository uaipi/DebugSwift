import SwiftUI

struct DebugRenderCount: Decodable {
    let name: String
    let count: Int
}

/// Render activity: Compose recompositions on Android, SwiftUI hosting-view renders on iOS. The
/// settings fields come only from iOS, where tracking is switched on here and draws a border on
/// each view as it renders.
struct DebugComposeState: Decodable {
    let total: Int
    let recomposers: Int
    let perSecond: [Int]
    let probeRenders: Int
    let frames: Int
    var tracking: Bool? = nil
    var persistent: Bool? = nil
    var logging: Bool? = nil
    var style: String? = nil
    var views: [DebugRenderCount]? = nil
}

/// How often the UI renders, sampled once a second while this screen is open. High, steady rates
/// on a still screen point at state that changes more than it should.
struct DebugComposeRendersView: View {
    @State var state: DebugComposeState? = nil
    @State var failure = ""
    @State var status = ""

    var rates: [Double] {
        (state?.perSecond ?? []).map { Double($0) }
    }

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if let state {
                if let tracking = state.tracking {
                    settings(state, tracking: tracking)
                }
                Section {
                    DebugMetricCard(
                        title: DebugPlatform.isAndroid ? "Recompositions per second" : "Renders per second",
                        value: "\(state.perSecond.last ?? 0)",
                        history: history,
                        color: Color.purple,
                    )
                }
                Section("Totals") {
                    LabeledContent(DebugPlatform.isAndroid ? "Recompositions since start" : "Renders since start") {
                        Text(verbatim: "\(state.total)")
                    }
                    LabeledContent("Busiest second") { Text(verbatim: "\(state.perSecond.max() ?? 0)") }
                    LabeledContent("Average, last minute") {
                        Text(verbatim: String(format: "%.1f", rates.isEmpty ? 0 : rates.reduce(0, +) / Double(rates.count)))
                    }
                    LabeledContent(DebugPlatform.isAndroid ? "Compose roots running" : "Views rendered") {
                        Text(verbatim: "\(state.recomposers)")
                    }
                    LabeledContent("Frames drawn") { Text(verbatim: "\(state.frames)") }
                    if state.probeRenders > 0 {
                        LabeledContent(DebugPlatform.isAndroid ? "Counted by a DebugSwiftComposeProbe" : "Counted by .trackRenders()") {
                            Text(verbatim: "\(state.probeRenders)")
                        }
                    }
                }
                if let views = state.views, !views.isEmpty {
                    Section("Most rendered views") {
                        ForEach(0..<views.count, id: \.self) { index in
                            HStack {
                                Text(verbatim: views[index].name)
                                    .font(.system(.footnote, design: .monospaced))
                                    .lineLimit(2)
                                Spacer()
                                Text(verbatim: "\(views[index].count)")
                                    .foregroundColor(Color.secondary)
                            }
                        }
                    }
                }
                Section {
                    Text(verbatim: DebugPlatform.isAndroid
                        ? "Counts every change Compose applies in this app, with no wrapper in your UI. Wrap a screen in DebugSwiftComposeProbe to count renders of just that screen."
                        : "Counts SwiftUI hosting views each time UIKit lays them out, and outlines each one on screen as it renders. Add .trackRenders() to a view to count that view alone.")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
            }
        }
        .navigationTitle(DebugPlatform.isAndroid ? "Compose Render Tracking" : "SwiftUI Render Tracking")
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    @ViewBuilder
    func settings(_ state: DebugComposeState, tracking: Bool) -> some View {
        Section {
            Toggle("Track SwiftUI renders", isOn: Binding(
                get: { tracking },
                set: { on in act("tracking", on ? "true" : "false") },
            ))
            if tracking {
                Picker("Highlight", selection: Binding(
                    get: { state.style ?? "count" },
                    set: { style in act("style", style) },
                )) {
                    Text("Border and count").tag("count")
                    Text("Border").tag("border")
                    Text("None").tag("none")
                }
                Toggle("Keep borders on screen", isOn: Binding(
                    get: { state.persistent ?? false },
                    set: { on in act("persistent", on ? "true" : "false") },
                ))
                Toggle("Log renders to the console", isOn: Binding(
                    get: { state.logging ?? false },
                    set: { on in act("logging", on ? "true" : "false") },
                ))
            }
            Button("Clear counts", role: .destructive) { act("clear", "") }
            if !status.isEmpty {
                Text(verbatim: status).font(.caption)
            }
        }
    }

    var history: DebugMetricHistory {
        var result = DebugMetricHistory()
        for value in rates { result.append(value) }
        return result
    }

    func act(_ actionID: String, _ value: String) {
        status = DebugSwiftRuntime.perform(featureID: "swiftui_render", actionID: actionID, value: value)
        refresh()
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
