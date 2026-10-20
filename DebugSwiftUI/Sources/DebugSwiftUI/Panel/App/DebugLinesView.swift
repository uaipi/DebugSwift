import SwiftUI

/// A tool whose snapshot is one entry per line (the event timeline), with a text filter.
struct DebugLinesView: View {
    let featureID: String
    let title: String
    @State var lines: [String] = []
    @State var filter = ""

    var visible: [String] {
        filter.isEmpty ? lines : lines.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        List {
            Section {
                TextField("Filter", text: $filter)
                Button("Refresh") { load() }
            }
            ForEach(0..<visible.count, id: \.self) { index in
                Text(verbatim: visible[index])
                    .font(.system(.footnote, design: .monospaced))
            }
        }
        .navigationTitle(Text(verbatim: title))
        .onAppear { load() }
    }

    func load() {
        lines = DebugSwiftAndroidRuntime.snapshot(featureID: featureID)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }
}
