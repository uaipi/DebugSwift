import SwiftUI

/// A small box drawn over the app with live CPU, frame rate and slow-frame counts.
struct DebugPerformanceWidgetView: View {
    @State var isShown = false
    @State var status = ""

    var body: some View {
        List {
            Section {
                Toggle("Show the widget over the app", isOn: Binding(
                    get: { isShown },
                    set: { shown in set(shown) },
                ))
                Text(verbatim: "The widget sits on the app's own window, so it needs no extra permission. Close this panel to see it.")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }
            if !status.isEmpty {
                Section("Status") {
                    Text(verbatim: status).font(.caption)
                }
            }
        }
        .navigationTitle("Performance Widget")
        .onAppear { refresh() }
    }

    func refresh() {
        isShown = DebugSwiftAndroidRuntime.snapshot(featureID: "performance_widget").hasPrefix("Widget is active")
    }

    func set(_ shown: Bool) {
        guard shown != isShown else { return }
        status = DebugSwiftAndroidRuntime.perform(featureID: "performance_widget", actionID: "toggle")
        refresh()
    }
}
