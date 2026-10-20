import SwiftUI

/// Actions the host app registered with the Kotlin tools, each with a button to run it.
struct DebugCustomActionsView: View {
    @State var titles: [String] = []
    @State var status = ""

    var body: some View {
        List {
            if titles.isEmpty {
                Text(verbatim: "No custom actions registered by the host app.")
                    .foregroundColor(Color.secondary)
            }
            ForEach(0..<titles.count, id: \.self) { index in
                Button(titles[index]) {
                    status = DebugSwiftAndroidRuntime.perform(
                        featureID: "custom_actions",
                        actionID: "run_custom",
                        value: titles[index],
                    )
                }
            }
            if !status.isEmpty {
                Section("Status") {
                    Text(verbatim: status).font(.caption)
                }
            }
        }
        .navigationTitle("Custom Actions")
        .onAppear { load() }
    }

    func load() {
        titles = DebugSwiftAndroidRuntime.snapshot(featureID: "custom_actions")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.hasPrefix("No custom actions") }
    }
}
