import SwiftUI

/// Android crashes with SuperNotCalledException when a lifecycle override forgets its super call.
struct DebugSuperCallsView: View {
    @State var crashes: [String] = []
    @State var failure = ""

    var body: some View {
        List {
            Section {
                Text(verbatim: "Android reports a missing required super call as a SuperNotCalledException. The crashes below mention one.")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            Section("Crashes with a missing super call") {
                if crashes.isEmpty {
                    Text(verbatim: "None captured.")
                        .foregroundColor(Color.secondary)
                }
                ForEach(0..<crashes.count, id: \.self) { index in
                    NavigationLink {
                        DebugTextDetailView(title: "Crash report", text: crashes[index])
                    } label: {
                        Text(verbatim: String(crashes[index].split(separator: "\n").first ?? "Crash report"))
                            .lineLimit(2)
                    }
                }
            }
            Section {
                Button("Refresh") { load() }
            }
        }
        .navigationTitle("Lifecycle Super Calls")
        .onAppear { load() }
    }

    func load() {
        switch DebugPerformanceDetail.fetch("supercalls", as: DebugSuperCallDetail.self) {
        case let .success(value):
            crashes = value.crashes
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}
