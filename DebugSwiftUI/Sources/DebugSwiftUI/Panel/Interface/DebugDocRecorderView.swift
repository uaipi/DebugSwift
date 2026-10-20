import SwiftUI

struct DebugGesture: Decodable {
    let kind: String
    let startX: Double
    let startY: Double
    let endX: Double
    let endY: Double
}

struct DebugDocState: Decodable {
    let recording: Bool
    let density: Double
    let gestures: [DebugGesture]
    let screenshot: String
    let message: String
}

/// Records taps and scrolls on the app, then saves a screenshot with each one numbered and, for
/// scrolls, an arrow: material for a how-to or a bug report.
struct DebugDocRecorderView: View {
    @State var state: DebugDocState? = nil
    @State var failure = ""
    @State var status = ""

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            Section {
                Toggle("Record taps and scrolls", isOn: Binding(
                    get: { state?.recording ?? false },
                    set: { on in record(on) },
                ))
                Text(verbatim: "Turn it on, close this panel, use the app, then come back to capture.")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }
            if let state {
                Section("Recorded gestures (\(state.gestures.count))") {
                    if state.gestures.isEmpty {
                        Text(verbatim: "Nothing recorded yet.")
                            .foregroundColor(Color.secondary)
                    }
                    ForEach(0..<state.gestures.count, id: \.self) { index in
                        Text(verbatim: "\(index + 1). \(describe(state.gestures[index], density: state.density))")
                            .font(.system(.footnote, design: .monospaced))
                    }
                }
                Section {
                    Button("Capture an annotated screenshot") { capture() }
                    Button("Clear", role: .destructive) {
                        _ = DebugPerformanceDetail.act("app.doc.clear")
                        load()
                    }
                    if !state.screenshot.isEmpty {
                        Button("Share the last screenshot") {
                            status = DebugSwiftAndroidRuntime.perform(featureID: "doc_recorder", actionID: "export")
                        }
                    }
                    if !status.isEmpty {
                        Text(verbatim: status).font(.caption)
                    }
                }
                if !state.screenshot.isEmpty {
                    Section("Last screenshot") {
                        AsyncImage(url: URL(fileURLWithPath: state.screenshot)) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Text(verbatim: state.screenshot).font(.caption)
                        }
                    }
                }
            }
        }
        .navigationTitle("Documentation Recorder")
        .onAppear { load() }
    }

    func describe(_ gesture: DebugGesture, density: Double) -> String {
        func dp(_ value: Double) -> Int { Int((value / max(density, 0.1)).rounded()) }
        if gesture.kind == "scroll" {
            return "Scroll (\(dp(gesture.startX)), \(dp(gesture.startY))) to (\(dp(gesture.endX)), \(dp(gesture.endY))) dp"
        }
        return "Tap at (\(dp(gesture.endX)), \(dp(gesture.endY))) dp"
    }

    func record(_ on: Bool) {
        _ = DebugPerformanceDetail.act("app.doc.record", ["on": on ? "true" : "false"])
        load()
    }

    func capture() {
        status = DebugPerformanceDetail.act("app.doc.capture")
        // The screen is copied a couple of frames later, so wait for the result to land.
        Task {
            for _ in 0..<12 {
                try? await Task.sleep(nanoseconds: 400_000_000)
                load()
                if let message = state?.message, !message.isEmpty {
                    status = message
                    return
                }
            }
        }
    }

    func load() {
        switch DebugResourceClient.fetch("app.doc.state", as: DebugDocState.self) {
        case let .success(value):
            state = value
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}
